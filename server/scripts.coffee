###
  Random scripting methods that
  TODO need to be moved into more generalized APIs
###

tutorialThresholdMins = 5
tutorialThresholdMillis = tutorialThresholdMins * 60 * 1000

checkTutorial = (asstRecord) ->
  # TODO: check for amount of time spent on exit survey
  instance = TurkServer.Instance.getInstance(asstRecord.instances[0].id)

  if instance.getDuration() < tutorialThresholdMillis
    throw new Error("Worker #{asstRecord.workerId} rushed through tutorial in under #{tutorialThresholdMins} minutes in #{instance.groupId}")

  startTime = Experiments.findOne(instance.groupId).startTime

  # Check for very short average time between actions
  actionIntervals = []
  prevActionTime = null

  Logs.find({
    _groupId: instance.groupId
    _meta: null
  }, {
    sort: {_timestamp: 1}
  }).forEach (log) ->
    if log._timestamp - startTime < 30000
      throw new Error("Worker #{asstRecord.workerId} time to first tutorial action was less than 30 sec in #{instance.groupId}")
    actionIntervals.push(log._timestamp - prevActionTime) if prevActionTime?
    prevActionTime = log._timestamp

  if actionIntervals.length < 10
    throw new Error("Worker #{asstRecord.workerId} did less than 10 actions in #{instance.groupId}")

  if actionIntervals.length < 18 and
  _.filter(actionIntervals, (t) -> t < 20000).length > 0.75 * actionIntervals.length
    throw new Error("Worker #{asstRecord.workerId} had 75% of actions under 20 sec in #{instance.groupId}")

approveMessage =
"""Thanks for doing our tutorial. Feel free to reach out to me personally if you have any questions or comments.

     If you asked to be notified, we'll send you an e-mail to let you of future crisis mapping tasks, and we hope you'll join us.
  """
rejectMessage = "Sorry, it looks like you weren't paying attention during the tutorial."

Meteor.methods

  # For testing purposes
  "cm-inject-fake-users": (batchId, count) ->
    TurkServer.checkAdmin()
    check(batchId, String)
    check(count, Match.Integer)

    for i in [1..count]
      workerId = Random.id()
      userId = Accounts.insertUserDoc {}, { workerId }
      asst = TurkServer.Assignment.createAssignment
        batchId: batchId
        hitId: Random.id()
        assignmentId: Random.id()
        workerId: workerId
        acceptTime: new Date()
        status: "assigned"

      # Throw into the assignment mechanism
      asst._enterLobby()

  "cm-evaluate-recruiting-tutorials": (actuallyPay) ->
    TurkServer.checkAdmin()
    batch = Batches.findOne(treatments: "recruiting")

    # TODO: move this functionality into TurkServer
    Assignments.find({
      batchId: batch._id
      status: "completed"
      mturkStatus: $in: [null, "Submitted"]
    }).forEach (a) ->

      asst = TurkServer.Assignment.getAssignment(a._id)

      if actuallyPay and not asst._data().mturkStatus
        # Make sure it's in submitted state
        return unless asst.refreshStatus() is "Submitted"

      try
        checkTutorial(a)
      catch e
        console.log e.toString()
        # We'll just let these auto-approve with no message and deny the qual later.
        # asst.reject(rejectMessage) if actuallyPay
        return

      asst.approve(approveMessage) if actuallyPay

  "cm-tutorial-first-action": ->
    TurkServer.checkAdmin()
    batch = Batches.findOne(treatments: "recruiting")

    timesToFirstAction = []

    Assignments.find({
      batchId: batch._id
      status: "completed"
      mturkStatus: $in: [null, "Submitted"]
    }).forEach (a) ->

      groupId = a.instances[0].id
      startTime = Experiments.findOne(groupId).startTime
      firstAction = Logs.findOne({
        _groupId: groupId
        _meta: null
      }, {
        sort: {_timestamp: 1}
      })._timestamp

      timesToFirstAction.push(firstAction - startTime)

    return timesToFirstAction

  "cm-tutorial-completed-time": ->
    TurkServer.checkAdmin()
    batch = Batches.findOne(treatments: "recruiting")

    durations = []

    Assignments.find({
      batchId: batch._id
      status: "completed"
      mturkStatus: $in: [null, "Submitted"]
    }).forEach (a) ->

      durations.push TurkServer.Instance.getInstance(a.instances[0].id).getDuration()

    return durations

  # Select random workers for a given e-mail
  "cm-select-random-email": (emailId, count, qualId, qualValue=1) ->
    TurkServer.checkAdmin()
    check(emailId, String)
    check(count, Match.Integer)
    check(qualId, String)
    check(qualValue, Match.Integer)

    potentialWorkers = Workers.find({
      contact: true
      quals:
        $elemMatch: {
          id: qualId
          value: qualValue
        }
    }).map (w) -> w._id

    # TODO either update quals or do not select workers who have done the task
    # already

    Meteor._debug "#{potentialWorkers.length} panel workers found with #{qualId} equal to #{qualValue}"

    selectedWorkers = _.sample(potentialWorkers, count)

    Meteor._debug "#{selectedWorkers.length} selected"

    WorkerEmails.update emailId,
      $set: recipients: selectedWorkers
    return

  "cm-update-quals": (qualId, actuallyAssign) ->
    TurkServer.checkAdmin()
    check(qualId, String)

    @unblock() # This may take a while

    # First update qual value to 2 for workers who have completed batches
    # TODO check if this case still holds after the group size experiment
    # TODO don't count workers who have been in the messed up batch
    experimentBatches = Batches.find({
      treatments: "parallel_worlds"
    }).map (batch) -> batch._id

    qualUpdates = 0

    Assignments.find({
      batchId: { $in: experimentBatches }
      submitTime: { $exists: true }
    }).forEach (asst) ->
      # Skip if qual is already value 2
      return if Workers.findOne({
        _id: asst.workerId,
        quals: {
          $elemMatch:
            id: qualId,
            value: 2
        }
      })?

      qualUpdates++
      TurkServer.Util.assignQualification(asst.workerId, qualId, 2, false) if actuallyAssign

    console.log("#{qualUpdates} workers updated to qual value 2")

    potentialWorkers = Workers.find({
      "quals.id": $nin: [qualId]
    }).map (w) -> w._id

    console.log("#{potentialWorkers.length} potential workers for new quals")

    recruitingBatchId = Batches.findOne(treatments: "recruiting")._id

    # Check that assignments are acceptable
    count = 0
    for workerId in potentialWorkers
      asst = Assignments.findOne({
        workerId,
        batchId: recruitingBatchId,
        submitTime: {$exists: true}
      })
      unless asst?
        console.log "Worker #{workerId} has contact=true but no assignment"
        continue

      try
        checkTutorial(asst)

        TurkServer.Util.assignQualification(workerId, qualId, 1, false) if actuallyAssign
        count++
      catch e
        console.log e.toString()

    console.log(count + " new quals assigned")

  "cm-pay-fuckup-bonus": (batchId, fromDate, toDate=new Date, actuallyPay=false) ->
    TurkServer.checkAdmin()

    paidWorkers = 0

    # Find accepted assignments from the problem batch
    Assignments.find({
      batchId,
      acceptTime: {
        $gte: fromDate
        $lte: toDate
      },
      endTime: null
    }).forEach (asst) ->

      paidWorkers++

      prevAsst = Assignments.findOne({
        workerId: asst.workerId,
        submitTime: { $exists: true }
      }, { sort: submitTime: -1 })

      user = Meteor.users.findOne({workerId: prevAsst.workerId})
      prevAsstObj = TurkServer.Assignment.getAssignment(prevAsst._id)

      message =
      """Dear #{user.username},

          Thank you for taking the time to work on the crisis mapping HIT today. We experienced technical difficulties as a result of having too many simultaneous connections to our server, and so we had to shut down the HIT.

          We value your time, so please accept this bonus along with our apologies for the inconvenience. We'll let you know of future opportunities to participate in the HIT.

          Best regards,
          Andrew/Sid
      """

      if actuallyPay
        prevAsstObj.setPayment(6.00)
        prevAsstObj.payBonus(message)
      else
        console.log message

    console.log "#{paidWorkers} workers compensated"

  "cm-pay-group-bonus": (groupId, ratio, extraFeedback, actuallyPay) ->
    TurkServer.checkAdmin()

    exp = TurkServer.Instance.getInstance(groupId)
    batch = exp.batch()

    treatmentData = exp.treatment()
    hourlyWage = treatmentData.wage + (ratio * treatmentData.bonus)
    console.log "hourly wage: " + hourlyWage

    millisPerHour = 3600 * 1000

    for userId in exp.users()
      user = Meteor.users.findOne(userId)
      asstId = Assignments.findOne({batchId: batch.batchId, workerId: user.workerId})._id
      asst = TurkServer.Assignment.getAssignment(asstId)
      continue unless asst.isCompleted()

      # Compute wage and make a message here
      instanceData = _.find(asst._data()?.instances, (inst) -> inst.id is groupId)

      totalTime = (instanceData.leaveTime - instanceData.joinTime)
      idleTime = (instanceData.idleTime || 0)
      disconnectedTime = (instanceData.disconnectedTime || 0)

      activeTime = totalTime - idleTime - disconnectedTime

      hourlyWageStr = hourlyWage.toFixed(2)
      payment = +(hourlyWage * activeTime / millisPerHour).toFixed(2)

      activeStr = TurkServer.Util.formatMillis(activeTime)
      idleStr = TurkServer.Util.formatMillis(idleTime)
      discStr = TurkServer.Util.formatMillis(disconnectedTime)

      message =
      """Dear #{user.username},

          Thank you very much for participating in the crisis mapping session. We sincerely appreciate your effort and feedback.\n\n
      """

      if extraFeedback?
        message +=
        """
          #{extraFeedback}\n\n
        """

      message +=
      """
          Your team earned an hourly wage of $#{hourlyWageStr}. You participated for #{activeStr}, not including idle time of #{idleStr} and disconnected time of #{discStr}. For your work, you are receiving a bonus of $#{payment.toFixed(2)}.

          Please free to send me a message if you have any other questions about the task or your payment.

          Sincerely,
          Andrew & Sid
        """

      console.log message
      throw new Error("The world is about to end") if payment > 16

      if (actuallyPay)
        asst.setPayment(payment)
        asst.payBonus(message)




