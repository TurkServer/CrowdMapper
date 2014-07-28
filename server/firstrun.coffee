loadEventFields = ->
  EventFields.insert
    "key": "type",
    "name": "Type",
    "order": 1,
    "type": "dropdown",
    "choices": [
      "Damaged bridges",
      "Damaged crops",
      "Damaged hospitals/health facilities",
      "Damaged housing",
      "Damaged roads",
      "Damaged schools",
      "Damaged vehicles",
      "Damaged infrastructure (other)",
      "Death(s) reported",
      "Displaced population",
      "Evacuation center",
      "Flooding"
    ]

  EventFields.insert
    "key": "description",
    "name": "Description",
    "order": 2,
    "type": "text"

  EventFields.insert
    "key": "region",
    "name": "Region",
    "order": 3,
    "type": "dropdown",
    "choices": [
      "ARMM - Autonomous Region in Muslim Mindanao",
      "CAR - Cordillera Administrative Region",
      "NCR - National Capital Region",
      "REGION I (Ilocos Region)",
      "REGION II (Cagayan Valley)",
      "REGION III (Central Luzon)",
      "REGION IV-A (Calabarzon)",
      "REGION IV-B (Mimaropa)",
      "REGION V (Bicol Region)",
      "REGION VI (Western Visayas)",
      "REGION VII (Central Visayas)",
      "REGION VIII (Eastern Visayas)",
      "REGION IX (Zamboanga Peninsula)",
      "REGION X (Northern Mindanao)",
      "REGION XI (Davao Region)",
      "REGION XII (Soccsksargen)",
      "REGION XIII (Caraga)"
    ]

  EventFields.insert
    "key": "province",
    "name": "Province",
    "order": 4,
    "type": "dropdown",
    "choices": [
      "Abra",
      "Agusan del Norte",
      "Agusan del Sur",
      "Aklan",
      "Albay",
      "Antique",
      "Apayao",
      "Aurora",
      "Basilan",
      "Bataan",
      "Batanes",
      "Batangas",
      "Benguet",
      "Biliran",
      "Bohol",
      "Bukidnon",
      "Bulacan",
      "Cagayan",
      "Camarines Norte",
      "Camarines Sur",
      "Camiguin",
      "Capiz",
      "Catanduanes",
      "Cavite",
      "Cebu",
      "Compostela Valley",
      "Cotabato",
      "Davao del Norte",
      "Davao del Sur",
      "Davao Oriental",
      "Dinagat Islands",
      "Eastern Samar",
      "Guimaras",
      "Ifugao",
      "Ilocos Norte",
      "Ilocos Sur",
      "Iloilo",
      "Isabela",
      "Kalinga",
      "La Union",
      "Laguna",
      "Lanao del Norte",
      "Lanao del Sur",
      "Leyte",
      "Maguindanao",
      "Marinduque",
      "Masbate",
      "Metro Manila",
      "Misamis Occidental",
      "Misamis Oriental",
      "Mountain Province",
      "Negros Occidental",
      "Negros Oriental",
      "Northern Samar",
      "Nueva Ecija",
      "Nueva Vizcaya",
      "Occidental Mindoro",
      "Oriental Mindoro",
      "Palawan",
      "Pampanga",
      "Pangasinan",
      "Quezon",
      "Quirino",
      "Rizal",
      "Romblon",
      "Samar",
      "Sarangani",
      "Siquijor",
      "Sorsogon",
      "South Cotabato",
      "Southern Leyte",
      "Sultan Kudarat",
      "Sulu",
      "Surigao del Norte",
      "Surigao del Sur",
      "Tarlac",
      "Tawi-Tawi",
      "Zambales",
      "Zamboanga del Norte",
      "Zamboanga del Sur",
      "Zamboanga Sibugay"
    ]

Meteor.startup ->
  return if EventFields.find().count() > 0

  loadEventFields()

# Set up treatments
Meteor.startup ->
  TurkServer.ensureTreatmentExists
    name: "tutorial"
    tutorial: "pre_task"
    tutorialEnabled: true
    payment: 1.00

  TurkServer.ensureTreatmentExists
    name: "recruiting"
    tutorial: "recruiting"
    tutorialEnabled: true
    payment: 1.00

  TurkServer.ensureTreatmentExists
    name: "parallel_worlds"
    wage: 6.00
    bonus: 9.00

  # Create Assigner on recruiting batch, if it exists
  if (batch = Batches.findOne(treatments: $in: [ "recruiting" ]))?
    TurkServer.Batch.getBatch(batch._id).setAssigner(new TurkServer.Assigners.SimpleAssigner)
    console.log "Set up assigner on recruiting batch"

    # Ensure we have a hit type on this batch
    HITTypes.upsert {
      batchId: batch._id,
      Title: "Complete a tutorial for the Crisis Mapping Project"
    }, {
      $setOnInsert: {
        Description: "Complete a tutorial for the Crisis Mapping Project, which takes about 10 minutes. After you complete this, you will be qualified to participate in collaborative Crisis Mapping sessions, which will pay from $6 to $15 per hour. You may see some disturbing content from natural disasters."
        Keywords: "crisis mapping, tutorial, collaborative"
        Reward: 1.00
        QualificationRequirement: [
          Qualifications.findOne({ # 95%
            QualificationTypeId: "000000000000000000L0"
            Comparator: "GreaterThanOrEqualTo"
            IntegerValue: "95"
          })._id
          Qualifications.findOne({ # 100 HITs
            QualificationTypeId: "00000000000000000040"
            Comparator: "GreaterThan"
            IntegerValue: "100"
          })._id
          Qualifications.findOne({ # US Worker
            QualificationTypeId: "00000000000000000071"
            Comparator: "EqualTo"
            LocaleValue: "US"
          })._id
          Qualifications.findOne({ # Adult Worker
            QualificationTypeId: "00000000000000000060"
            Comparator: "EqualTo"
            IntegerValue: "1"
          })._id
        ]
        AssignmentDurationInSeconds: 43200
        AutoApprovalDelayInSeconds: 86400
      }
    }

  # Set up pilot testing batch
  TurkServer.ensureBatchExists
    name: "pilot testing"

  pilotBatchId = Batches.findOne(name: "pilot testing")._id

  Batches.upsert pilotBatchId,
    $addToSet: { treatments: "parallel_worlds" }

  pilotBatch = TurkServer.Batch.getBatch(pilotBatchId)
  pilotBatch.setAssigner new TurkServer.Assigners.TutorialGroupAssigner(
    [ "tutorial" ], [ "parallel_worlds" ]
  )
  console.log "Set up pilot testing assigner"

###
  Random scripting methods that
  TODO need to be moved into more generalized APIs
###

tutorialThresholdMins = 5
tutorialThresholdMillis = tutorialThresholdMins * 60 * 1000

checkTutorial = (asstRecord) ->
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
  _.filter(actionIntervals, (t) -> t < 15000).length > 0.5 * actionIntervals.length
    throw new Error("Worker #{asstRecord.workerId} had 50% of actions under 10 sec in #{instance.groupId}")

approveMessage = "Thanks for your work!"
rejectMessage = "Sorry, it looks like you weren't paying attention during the tutorial."

Meteor.methods
  "cm-evaluate-recruiting-tutorials": (actuallyPay) ->
    TurkServer.checkAdmin()
    batch = Batches.findOne(treatments: "recruiting")

    Assignments.find({
      batchId: batch._id
      status: "completed"
      mturkStatus: $in: [null, "Submitted"]
    }).forEach (a) ->

      asst = TurkServer.Assignment.getAssignment(a._id)

      if actuallyPay
        # Make sure it's in submitted state
        asst.refreshStatus() unless asst._data().mturkStatus

      try
        checkTutorial(a)
        asst.approve(approveMessage) if actuallyPay
      catch e
        console.log e.toString()
        asst.reject(rejectMessage) if actuallyPay

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

  "cm-assign-tutorial-quals": (qualId) ->
    TurkServer.checkAdmin()
    check(qualId, String)

    @unblock() # This may take a while

    potentialWorkers = Workers.find({
      contact: true
      "quals.id": $nin: [qualId]
    }).map (w) -> w._id

    console.log(potentialWorkers.length + " potential workers to assign quals")

    batchId = Batches.findOne(treatments: "recruiting")._id

    # Check that assignments are acceptable
    count = 0
    for workerId in potentialWorkers
      asst = Assignments.findOne({workerId, batchId})
      unless asst?
        console.log "Worker #{workerId} has contact=true but no assignment"
        continue

      try
        checkTutorial(asst)

        TurkServer.Util.assignQualification(workerId, qualId)
        count++
      catch e
        console.log e.toString()

    console.log(count + " workers assigned")





