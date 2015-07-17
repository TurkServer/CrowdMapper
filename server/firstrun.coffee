Meteor.startup ->
  return if EventFields.find().count() > 0

  pabloFields = Assets.getText("fields-pablo.json")

  EventFields.insert(field) for field in JSON.parse(pabloFields)

# Load gold standard data if it exists
tryImport = (worldName) ->
  if Experiments.findOne(worldName)?
    console.log("#{worldName} already exists, skipping import")
    return
  result = JSON.parse Assets.getText("#{worldName}.json")

  Experiments.upsert(worldName, $set: { treatments: [ "editable" ] })

  for event in result.events
    event._groupId = worldName
    Events.direct.insert(event)

  for data in result.datastream
    data._groupId = worldName
    Datastream.direct.insert(data)

  console.log "Imported #{worldName}; events: #{result.events.length}, datastream: #{result.datastream.length}"

Meteor.startup -> tryImport("groundtruth-pablo")
Meteor.startup -> tryImport("sbtf-pablo")

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
    # Enable re-attempts on recruiting batch if returned
    Batches.update batch._id,
      $set: allowReturns: true

    TurkServer.Batch.getBatch(batch._id).setAssigner(new TurkServer.Assigners.SimpleAssigner)
    console.log "Set up assigner on recruiting batch"

    # Ensure we have a hit type on this batch
    HITTypes.upsert {
      batchId: batch._id,
      Title: "Complete a tutorial for the Crisis Mapping Project"
    }, {
      $setOnInsert: {
        Description: "Complete a tutorial for the Crisis Mapping Project, which takes about 10 minutes. After you complete this, you will be qualified to participate in collaborative Crisis Mapping sessions, which will pay from $6 to $15 per hour. You may see some disturbing content from natural disasters.

        You cannot do this HIT if you've done it before. If you accept it again, you will be asked to return it."
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

  # Set up pilot testing batch - currently disabled
  if Meteor.settings.pilot

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
    Set up group size experiments! Yay!

    Old group size batch was "group sizes" which we are discarding, because no
    one got through it during this server crash.

    This is the new one.
  ###
  groupSizeBatchName = "group sizes redux"

  if Meteor.settings.experiment or Batches.findOne({name: groupSizeBatchName})?
    TurkServer.ensureBatchExists
      name: groupSizeBatchName

    groupSizeBatchId = Batches.findOne(name: groupSizeBatchName)._id

    # Needed to trigger the right preview/exit survey
    Batches.upsert groupSizeBatchId,
      $addToSet: { treatments: "parallel_worlds" }

    groupBatch = TurkServer.Batch.getBatch(groupSizeBatchId)
    # 8x1, 4x2, 2x4, 1x8, 1x16, 1x32
    groupArray = [
      1, 1, 1, 1, 1, 1, 1, 1,
      2, 2, 2, 2,
      4, 4,
      8, 16, 32
    ]

    groupAssigner = new TurkServer.Assigners.TutorialRandomizedGroupAssigner(
      [ "tutorial" ], [ "parallel_worlds" ], groupArray)

    groupBatch.setAssigner(groupAssigner)

    Meteor._debug "Set up group size assigner"

  # Set up demo for SBTF
  if Meteor.settings.demo
    demoBatchName = "SBTF demo"

    TurkServer.ensureBatchExists({name: demoBatchName, active: true})

    demoBatchId = Batches.findOne({name: demoBatchName})._id

    # Create a new instance for this demo
    Experiments.update("sbtf-demo", {$set: {batchId: demoBatchId}})

    # Create a test assigner that puts everyone in this group
    demoBatch = TurkServer.Batch.getBatch(demoBatchId)
    demoBatch.setAssigner( new TurkServer.Assigners.TestAssigner() )

    console.log "Set up demo"

Meteor.methods
  "cm-delete-world-data": (worldId) ->
    TurkServer.checkAdmin()

    if Experiments.remove(worldId)
      Partitioner.bindGroup worldId, ->
        Events.remove({})
        Datastream.remove({})

    return

