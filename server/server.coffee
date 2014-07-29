###
  TurkServer-ed publications
  All of these publications check for grouping, except notifications
###

# User status and username
Meteor.publish "userStatus", ->
  ###
    The status field below should really be "status.online" to not publish random other status fields
    But we need to leave it at status because otherwise we will be missing fields on the merge.
    https://github.com/meteor/meteor/issues/998
  ###
  Meteor.users.find {}, # All users (in my group)
    fields:
      username: 1
      status: 1

# Publish all events, docs, and events, including deleted - filtering is done on the client
# This means admins can see deleted items easily, and they still work in chat

Meteor.publish "datastream", -> Datastream.find()

Meteor.publish "docs", -> Documents.find()

Meteor.publish "events", -> Events.find()

Meteor.publish 'notifications', ->
  # Only publish unread notifications for this user (in this instance)
  Notifications.find
    user: this.userId
    read: {$exists: false}

###
  Methods
###

Meteor.methods
  "finishTutorial": ->
    exp = TurkServer.Instance.currentInstance()
    # If finish button is mashed, this may not exist.
    unless exp?
      Meteor._debug("Finish tutorial: instance does not exist: ", this)
      return

    if exp.treatment()?.tutorialEnabled
      exp.teardown()

    return

  "getMapperData": (groupId) ->
    TurkServer.checkAdmin()

    instance =  Experiments.findOne(groupId)

    roomIds = Partitioner.directOperation ->
      ChatRooms.find(_groupId: groupId).map (room) -> room._id

    users = Meteor.users.find(_id: $in: instance.users).fetch()
    logs = Logs.find({_groupId: groupId}, {sort: {_timestamp: 1}}).fetch()
    chat = ChatMessages.find({room: $in: roomIds}, {sort: {timestamp: 1}}).fetch()

    return {instance, users, logs, chat}

  # TODO hack-ass method that needs to be re-implemented in a more generalized way
  "computePayment": (groupId, ratio, actuallyPay) ->
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

      # TODO Temporary workaround for buggy accounting
      idleTime = 0 if idleTime / millisPerHour > 0.2
      disconnectedTime = 0 if disconnectedTime / millisPerHour > 0.2

      activeTime = totalTime - idleTime - disconnectedTime

      hourlyWageStr = hourlyWage.toFixed(2)
      payment = +(hourlyWage * activeTime / millisPerHour).toFixed(2)

      activeStr = TurkServer.Util.formatMillis(activeTime)
      idleStr = TurkServer.Util.formatMillis(idleTime)
      discStr = TurkServer.Util.formatMillis(disconnectedTime)

      message =
        """Dear #{user.username},

          Thank you very much for participating in the crisis mapping session. We sincerely appreciate your effort and feedback.

          Your team earned an hourly wage of $#{hourlyWageStr}. You participated for #{activeStr}, not including idle time of #{idleStr} and disconnected time of #{discStr}. For your work, you are receiving a bonus of $#{payment.toFixed(2)}.

          Please free to send me a personal message if you have any other questions about the task or your payment.
        """

      console.log message
      throw new Error("The world is about to end") if payment > 11

      if (actuallyPay)
        asst.setPayment(payment)
        asst.payBonus(message)

