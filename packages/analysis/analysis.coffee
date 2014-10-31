# Collections for analysis
@AnalysisWorlds = new Meteor.Collection("analysis.worlds")
AnalysisPeople = new Meteor.Collection("analysis.people")

AnalysisPeople._ensureIndex({instanceId: 1, userId: 1})

AnalysisStats = new Meteor.Collection("analysis.stats")

# Special groundtruth tag for these instances
TurkServer.ensureTreatmentExists
  name: "groundtruth"

# Treatment tag added to enable admin editing of an instance
TurkServer.ensureTreatmentExists
  name: "editable"

###
  We can divide experiments into different (overlapping) categories:

  - Incomplete experiments, which are just ignored from analysis.
  - Non-treatment experiments, including buffers or non-random participants
  - Treatment experiments, which were treated and can be used for analysis.

  The gold standard can be constructed from treatment experiments and non-random groups.
  Weights can be computed from all but incomplete, as they are evenly applied to everyone.
  Stats should distinguish between treatment experiments and others we ignore.
  Treatment experiments don't need to have perfect grouping as we can normalize in different ways.
###

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
  # This includes ignored treatment groups, but not buffer groups
  return Experiments.find({
    batchId: batch._id
    treatments:
      $in: [
        "group_1", "group_2", "group_4", "group_8", "group_16", "group_32"
      ]
    users: $exists: true
  }).map (e) -> e._id

getAllExpIds = ->
  batch = Batches.findOne({name: "group sizes redux"})

  # Get all crisis mapping experiments that had users join
  return Experiments.find({
    batchId: batch._id
    treatments: "parallel_worlds"
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

  "cm-get-analysis-people": ->
    TurkServer.checkAdmin()
    return AnalysisPeople.find({treated: true}).fetch()

  # Copy the experiment worlds we're interested in to a new collection for
  # computing analysis results
  "cm-populate-analysis-worlds": (force) ->
    TurkServer.checkAdmin()

    unless force
      throw new Meteor.Error(400, "Worlds already exist") if AnalysisWorlds.find().count()

    AnalysisWorlds.remove({})
    AnalysisPeople.remove({})

    worlds = 0
    people = 0

    for expId in getAllExpIds()
      exp = Experiments.findOne(expId)

      # Ignore experiments where no one submitted (mostly groups of 1)
      unless Assignments.findOne({
        "instances.id": exp._id
        "status": "completed"
      })?
        console.log "Skipping #{exp._id} as no one completed it"
        continue

      # Is this a buffer group?
      if exp.treatments[0] is "parallel_worlds"
        # Fo these, round to closest power of 2 in log space
        exp.nominalSize = 1 << Math.round(Math.log(exp.users.length) / Math.LN2)
        exp.treated = false
      else
        # TODO this assumes that treatments[0] is of the form "group_xx"
        exp.nominalSize = parseInt(exp.treatments[0].substring(6))
        # Only the two extra groups of 16 are invalid treatment groups.
        exp.treated = exp.startTime > new Date("2014-08-08T12:00:00.000Z")

      AnalysisWorlds.insert(exp)
      worlds++

      # Insert a person record for each person that completed the assignment here
      for userId in exp.users
        user = Meteor.users.findOne(userId)

        # TODO put this into a TurkServer API
        if Assignments.findOne({
          workerId: user.workerId
          batchId: exp.batchId
          submitTime: $exists: true
        })?
          AnalysisPeople.insert({
            instanceId: exp._id
            userId: userId
          })
          people++

    console.log "Recorded #{worlds} instances, #{people} people"

  "cm-get-action-weights": (recompute) ->
    TurkServer.checkAdmin()

    if recompute or not (weights = AnalysisStats.findOne("actionWeights")?.weights)

      unless AnalysisWorlds.findOne()?
        console.log("No experiments specified for computing weights; grabbing some")
        Meteor.call("cm-populate-analysis-worlds")

      weightArrs = {}
      skipped = 0
      included = 0
      # Threshold for which we count action times.
      # 8 minute timeout used in actual experiments.
      forgetThresh = 8 * 60 * 1000

      batchId = Batches.findOne(name: "group sizes redux")._id
      # Compute weights just over treated groups.
      expIds = AnalysisWorlds.find({treated: true}).map (e) -> e._id

      for expId in expIds
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
              timestamp = nextLog._timestamp
              li++

              # Don't track meta events, but use them to update last time if active/connection
              if (meta = nextLog._meta)
                # Some of these may be janky, but helps prevent overestimating effort
                if meta is "active" or meta is "connected"
                  lastEventTime = timestamp

                continue

              # Ignore first action because we don't have ramp-up info
              actionTime = lastEventTime && (timestamp - lastEventTime)

              if actionTime < forgetThresh
                weightArrs[nextLog.action] ?= []
                weightArrs[nextLog.action].push(actionTime)

              lastEventTime = timestamp

            else if nextChat # next event for this user is chat
              timestamp = nextChat.timestamp
              ci++

              actionTime = lastEventTime && (timestamp - lastEventTime)

              if actionTime < forgetThresh
                weightArrs["chat"] ?= []
                weightArrs["chat"].push(actionTime)

              lastEventTime = timestamp

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

matchingScore = (events, gsEvents) ->
  scoring = []

  events.forEach (ev) ->
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

  return [ partialScore, strictScore ]

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

    for world in AnalysisWorlds.find().fetch()
      expId = world._id
      replay = new ReplayHandler(expId)

      replay.initialize(weights)

      # Initialize array with zeroes at time 0
      increments = [
        {
          wt: 0
          mt: 0
          ef: 0
          ps: 0
          ss: 0
        }
      ]

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
        [partialScore, strictScore] = matchingScore(
          replay.tempEvents.find({deleted: {$exists: false}}), gsEvents)

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

      # Save the performance for each user
      for userId, stats of replay.userEffort
        stats.treated = world.treated
        stats.groupSize = world.nominalSize
        stats.time /= 3600 * 1000
        stats.effort /= 3600 * 1000

        # This skips people that aren't in the db.
        AnalysisPeople.update {instanceId: expId, userId: userId},
          $set: stats

    Meteor._debug("Analysis complete.")

  # Compute performance of pseudo-aggregated groups, as in discussion with Peter.
  "cm-compute-pseudo-performance": ->
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

    for groupSize in [1, 2, 4, 8]
      console.log "Syncing replays of size #{groupSize} groups"

      replays = []

      for world in AnalysisWorlds.find({treated: true, nominalSize: groupSize}).fetch()
        expId = world._id
        replay = new ReplayHandler(expId)
        replay.initialize(weights)

        replays.push(replay)

      # Initialize array with zeroes at time 0
      increments = [
        {
          wt: 0
          mt: 0
          ef: 0
          ps: 0
          ss: 0
        }
      ]

      totalWallTime = 0
      totalManTime = 0

      # Advance all replays at the same wall time
      while _.all( replays, (r) -> r.nextEventTime()? )
        # Compute parameters every 5 wall-minutes or 15 man-minutes, whichever is smaller
        targetWallTime = totalWallTime + 5 * 60 * 1000
        targetManTime = totalManTime + 15 * 60 * 1000

        try
          while totalWallTime < targetWallTime && totalManTime < targetManTime
            # tick replay with the next valid event time
            minRep = _.min( replays, (r) -> (r.nextEventTime() - r.exp.startTime) || Infinity )
            minRep.processNext()

            # Recompute times
            totalWallTime = _.max(replays, (r) -> r.wallTime).wallTime
            totalManTime = _.reduce(replays, ((m, r) -> m + r.manTime), 0)
        catch e
          # console.log e

        # console.log totalWallTime
        # console.log( r.wallTime for r in replays )

        manEffort = _.reduce(replays, ((m, r) -> m + r.manEffort), 0)

        # Compute partial and strict scores
        aggEvents = []
        for r in replays
          aggEvents = aggEvents.concat( r.tempEvents.find({deleted: {$exists: false}}).fetch() )

        [partialScore, strictScore] = matchingScore(aggEvents, gsEvents)

        increments.push
          wt: totalWallTime / (3600 * 1000)
          mt: totalManTime / (3600 * 1000)
          ef: manEffort / (3600 * 1000)
          ps: partialScore
          ss: strictScore

      lastIncrement = increments[increments.length - 1]

      AnalysisWorlds.upsert {pseudo: true, treated: false, nominalSize: groupSize},
        $set:
          progress: increments
          wallTime: lastIncrement.wt
          personTime: lastIncrement.mt
          totalEffort: lastIncrement.ef
          partialCreditScore: lastIncrement.ps
          fullCreditScore: lastIncrement.ss

