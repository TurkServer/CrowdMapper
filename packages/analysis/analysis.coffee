# Collections for analysis
AnalysisWorlds = new Meteor.Collection("analysis.worlds")

AnalysisDatastream = new Meteor.Collection("analysis.datastream")
AnalysisEvents = new Meteor.Collection("analysis.events")

AnalysisStats = new Meteor.Collection("analysis.stats")

# Special groundtruth tag for these instances
TurkServer.ensureTreatmentExists
  name: "groundtruth"

# Treatment tag added to enable admin editing of an instance
TurkServer.ensureTreatmentExists
  name: "editable"

getLargeGroupExpIds = ->
  batch = Batches.findOne({name: "group sizes redux"})

  return Experiments.find({
    batchId: batch._id
    treatments: $in: [ "group_16", "group_32" ]
    users: $exists: true
  }).map (e) -> e._id

getGoldStandardExpIds = ->
  batch = Batches.findOne({name: "group sizes redux"})

  # Get the experiments that we will use to generate the gold standard
  # This includes off-cycle treatment groups, but not buffer groups
  return Experiments.find({
    batchId: batch._id
    treatments:
      $in: [
        "group_1", "group_2", "group_4", "group_8", "group_16", "group_32"
      ]
    users: $exists: true
  }).map (e) -> e._id

Meteor.methods
  "cm-get-viz-data": (groupId) ->
    TurkServer.checkAdmin()

    # Get weights for actions
    weights = Meteor.call("cm-get-action-weights")

    instance =  Experiments.findOne(groupId)

    roomIds = Partitioner.directOperation ->
      ChatRooms.find(_groupId: groupId).map (room) -> room._id

    users = Meteor.users.find(_id: $in: instance.users).fetch()
    logs = Logs.find({_groupId: groupId}, {sort: {_timestamp: 1}}).fetch()
    chat = ChatMessages.find({room: $in: roomIds}, {sort: {timestamp: 1}}).fetch()

    return {weights, instance, users, logs, chat}

  "cm-get-analysis-worlds": ->
    TurkServer.checkAdmin()

    return AnalysisWorlds.find().fetch()

  # Copy the experiment worlds we're interested in to a new collection for
  # computing analysis results
  "cm-populate-analysis-worlds": (force) ->
    TurkServer.checkAdmin()

    unless force
      throw new Meteor.Error(400, "Worlds already exist") if AnalysisWorlds.find().count()

    AnalysisWorlds.remove({})

    # TODO exclude the extra long/short bus groups of 16
    for expId in getGoldStandardExpIds()
      exp = Experiments.findOne(expId)

      # Ignore experiments where no one submitted (mostly groups of 1)
      unless Assignments.findOne({
        "instances.id": exp._id
        "status": "completed"
      })?
        console.log "Skipping #{exp._id} as no one completed it"
        continue

      # TODO this assumes that treatments[0] is of the form "group_xx"
      exp.nominalSize = parseInt(exp.treatments[0].substring(6))

      AnalysisWorlds.insert(exp)

  "cm-get-action-weights": (recompute) ->
    TurkServer.checkAdmin()

    if recompute or not (weights = AnalysisStats.findOne("actionWeights")?.weights)

      weightArrs = {}
      skipped = 0
      included = 0
      # Threshold for which we count action times.
      # 8 minute timeout used in actual experiments.
      forgetThresh = 8 * 60 * 1000

      batchId = Batches.findOne(name: "group sizes redux")._id

      for expId in getGoldStandardExpIds()
        exp = Experiments.findOne(expId)

        # All rooms for this experiment, including deleted ones
        roomIds = ChatRooms.direct.find(_groupId: expId).map (room) -> room._id

        for userId in exp.users
          user = Meteor.users.findOne(userId)

          # Did this person submit the HIT?
          # TODO put this into a TurkServer API
          unless Assignments.findOne({
            workerId: user.workerId
            batchId: batchId
            submitTime: $exists: true
          })?
            skipped++
            continue

          # Get all log and chat records for this user and iterate through them
          # TODO: consider doc edits as well.
          logEvents = Logs.find({_groupId: expId, _userId: userId},
            {sort: _timestamp: 1}).fetch()

          chatEvents = ChatMessages.find({room: {$in: roomIds}, userId: userId},
            {sort: {timestamp: 1}}).fetch()

          lastEventTime = null
          li = 0
          ci = 0

          while li < logEvents.length or ci < chatEvents.length
            nextLog = logEvents[li]
            nextChat = chatEvents[ci]

            if nextLog && nextLog._timestamp < (nextChat?.timestamp || Date.now())
              # Next event for this user is log
              li++

              continue if nextLog._meta

              # Ignore first action because we don't have ramp-up info
              # TODO: count when this person entered the room
              actionTime = lastEventTime && (nextLog._timestamp - lastEventTime)

              if actionTime < forgetThresh
                weightArrs[nextLog.action] ?= []
                weightArrs[nextLog.action].push(actionTime)

              lastEventTime = nextLog._timestamp

            else if nextChat # next event for this user is chat
              ci++

              actionTime = lastEventTime && (nextChat.timestamp - lastEventTime)

              if actionTime < forgetThresh
                weightArrs["chat"] ?= []
                weightArrs["chat"].push(actionTime)

              lastEventTime = nextChat.timestamp

          unless li is logEvents.length and ci is chatEvents.length
            console.log expId, userId
            console.log li, logEvents.length
            console.log ci, chatEvents.length
            throw new Error("Did not reach end of log or chat array")

          included++

      # Compute average weight for each action
      weights = {}

      for k, v of weightArrs
        weights[k] = _.reduce(v, ( (m, n) -> m + n), 0 ) / v.length

      console.log "Skipped #{skipped}, included #{included} workers"
      console.log weights

      AnalysisStats.upsert "actionWeights",
        $set: { weights }

    return weights

# Scoring function for an event. Current scheme is:
# 0.25 to type, 0.25 to region, 0.25 to province,
# 0.25 for within 10km to 0 beyond 100km
scoreEvent = (event, benchmark) ->
  s = 0

  for field in [ "type", "region", "province" ]
    if event[field] is benchmark[field]
      s += 0.25

  if event.location?
    a = event.location[0] - benchmark.location[0]
    b = event.location[1] - benchmark.location[1]
    meters = 0.1 + Math.sqrt(a * a + b * b)

    s += 0.25 * (1 - Math.max(0, Math.min(1, (Math.log(meters) / Math.LN10 - 4))))

  # Flip so it's a cost matrix, for munkres
  return 1 - s

# 0.33 = up to 1 field wrong and ~20km away
# < 0.24 = just errors in the location
errorThresh = 0.33

Meteor.methods
  # Compute group performance and effort over time for experiment worlds.
  "cm-compute-group-performance": ->
    TurkServer.checkAdmin()

    weights = Meteor.call("cm-get-action-weights")

    # Get gold standard events
    gsEvents = Events.direct.find({
      _groupId: "groundtruth-pablo",
      deleted: { $exists: false },
      # Some events in gold standard don't have location:
      # They are just being used to hold data, so ignore them.
      location: { $exists: true }
    }).fetch()

    for expId in AnalysisWorlds.find().map( (w) -> w._id )
      replay = new ReplayHandler(expId)

      replay.initialize(weights)

      increments = []

      while replay.nextEventTime()?
        # Compute parameters every 5 wall-minutes or 15 man-minutes, whichever is smaller
        targetWallTime = replay.wallTime + 5 * 60 * 1000
        targetManTime = replay.manTime + 15 * 60 * 1000

        try
          while replay.wallTime < targetWallTime && replay.manTime < targetManTime
            # This will throw an error if it runs out; giving us one final point
            replay.processNext()
        catch e

        # Compute partial and strict scores
        scoring = []

        replay.tempEvents.find({deleted: {$exists: false}}).forEach (ev) ->
          scoring.push( (scoreEvent(ev, gs) for gs in gsEvents) )

        if scoring.length
          partialScore = Analysis.invoke("maxMatching", scoring)

          # Clamp and compute strict score
          for row in scoring
            for i in [1...row.length]
              row[i] = if row[i] < errorThresh then 0 else 1

          strictScore = Analysis.invoke("maxMatching", scoring)
        else
          # If no events are created, don't RPC (errors with 0-length matrix)
          partialScore = 0
          strictScore = 0

        increments.push
          wt: replay.wallTime / (3600 * 1000)
          mt: replay.manTime / (3600 * 1000)
          ef: replay.manEffort / (3600 * 1000)
          ps: partialScore
          ss: strictScore

      replay.printStats()

      lastIncrement = increments[increments.length - 1]

      AnalysisWorlds.update expId,
        $set:
          progress: increments
          wallTime: lastIncrement.wt
          personTime: lastIncrement.mt
          totalEffort: lastIncrement.ef
          partialCreditScore: lastIncrement.ps
          fullCreditScore: lastIncrement.ss

    Meteor._debug("Analysis complete.")
