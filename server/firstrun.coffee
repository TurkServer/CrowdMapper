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
Meteor.methods
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
    threshold = 5
    count = 0
    for workerId in potentialWorkers
      asst = Assignments.findOne({workerId, batchId})
      unless asst?
        console.log "Worker #{workerId} has contact=true but no assignment"
        continue

      instance = Experiments.findOne(asst.instances[0].id)
      if (instance.endTime - instance.startTime) < threshold * 60 * 1000
        console.log "Worker #{workerId} rushed through tutorial in under #{threshold} minutes"
        continue

      TurkServer.Util.assignQualification(workerId, qualId)
      count++

    console.log(count + " workers assigned")





