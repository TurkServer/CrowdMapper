fs = Npm.require('fs');

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

# Admin data publications
Meteor.publish "cm-analysis-worlds", (filter) ->
  return [] unless TurkServer.isAdmin(this.userId)
  return Analysis.Worlds.find(filter || {})

Meteor.publish "cm-analysis-people", (filter) ->
  return [] unless TurkServer.isAdmin(this.userId)
  return Analysis.People.find({treated: true})

###
  Overview of analysis starting from the gold standard
  - copy experiment worlds and people into analysis collections
  - compute average weight of each action
  - score worlds over time
  - compute specialization
  - synthetic/pseudo groups TODO
###

Meteor.methods
  "cm-get-viz-data": (groupId) ->
    TurkServer.checkAdmin()

    # Get weights for actions
    weights = Meteor.call("cm-get-action-weights")

    instance =  Experiments.findOne(groupId)

    roomIds = ChatRooms.direct.find(_groupId: groupId).map (room) -> room._id

    users = Meteor.users.find(_id: $in: instance.users).fetch()
    logs = Logs.find({_groupId: groupId}, {sort: {_timestamp: 1}}).fetch()
    chat = ChatMessages.find({room: $in: roomIds}, {sort: {timestamp: 1}}).fetch()

    return {weights, instance, users, logs, chat}

  # Copy the experiment worlds we're interested in to a new collection for
  # computing analysis results
  "cm-populate-analysis-worlds": (force) ->
    TurkServer.checkAdmin()

    unless force
      throw new Meteor.Error(400, "Worlds already exist") if Analysis.Worlds.find().count()

    Analysis.Worlds.remove({})
    Analysis.People.remove({})

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

      Analysis.Worlds.insert(exp)
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
          Analysis.People.insert({
            instanceId: exp._id
            userId: userId
          })
          people++

    console.log "Recorded #{worlds} instances, #{people} people"

  "cm-get-action-weights": (recompute) ->
    TurkServer.checkAdmin()

    if recompute or not (weights = Analysis.Stats.findOne("actionWeights")?.weights)

      unless Analysis.Worlds.findOne()?
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
      expIds = Analysis.Worlds.find({treated: true}).map (e) -> e._id

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

      Analysis.Stats.upsert "actionWeights",
        $set: { weights }

    return weights

  # Output non-deleted events and status of data in the world to a file
  "cm-save-world-data": (worldId) ->
    TurkServer.checkAdmin()

    # we need to store _ids here because of cross referencing
    events = Events.direct.find({
      _groupId: worldId,
      deleted: { $exists: false },
    }, {
      sort: {num: 1}
      fields: { _groupId: 0 }
    }).fetch()

    data = Datastream.direct.find({
      _groupId: worldId
    }, {
      sort: {num: 1}
      fields: { _groupId: 0 }
    }).fetch()

    # some cleanup:
    for d in data
      # delete hidden field if events exists and length > 0
      delete d.hidden if d.hidden? and d.events?.length
      # delete empty events arrays
      delete d.events if d.events? and d.events.length is 0

    output = {
      events: events
      datastream: data
    }

    # Write to a file that won't cause Meteor to restart
    filename = ".#{worldId}.json"

    fs.writeFile filename, JSON.stringify(output, null, 2), (err) ->
      if err then console.log(err) else console.log "Output written to #{filename}"

# Get gold standard events
getGoldStandardEvents = ->
  return Events.direct.find({
    _groupId: "groundtruth-pablo",
    deleted: { $exists: false },
  # Some events in gold standard don't have location:
  # They are just being used to hold data, so ignore them.
    location: { $exists: true }
  }).fetch()

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
    partialScore = Analysis.invokeRPC("maxMatching", scoring)

    # Clamp and compute strict score
    for row in scoring
      for i in [0...row.length]
        row[i] = if row[i] < errorThresh then 0 else 1

    strictScore = Analysis.invokeRPC("maxMatching", scoring)
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

    gsEvents = getGoldStandardEvents()

    for world in Analysis.Worlds.find({pseudo: null, synthetic: null}).fetch()
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
          p: 0
          r: 0
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
        currentEvents = replay.tempEvents.find({deleted: {$exists: false}})
        eventCount = currentEvents.count()

        [partialScore, strictScore] = matchingScore(currentEvents, gsEvents)

        prec = if eventCount > 0 then strictScore / eventCount else 0
        rec = strictScore / gsEvents.length

        increments.push
          wt: replay.wallTime / (3600 * 1000)
          mt: replay.manTime / (3600 * 1000)
          ef: replay.manEffort / (3600 * 1000)
          ps: partialScore
          ss: strictScore
          p: prec
          r: rec

      replay.printStats()

      lastIncrement = increments[increments.length - 1]

      Analysis.Worlds.update expId,
        $set:
          progress: increments
          wallTime: lastIncrement.wt
          personTime: lastIncrement.mt
          totalEffort: lastIncrement.ef
          partialCreditScore: lastIncrement.ps
          fullCreditScore: lastIncrement.ss
          precision: lastIncrement.p
          recall: lastIncrement.r

      # Save the performance for each user
      for userId, stats of replay.userEffort
        stats.treated = world.treated
        stats.groupSize = world.nominalSize
        stats.time /= 3600 * 1000
        stats.effort /= 3600 * 1000

        # This skips people that aren't in the db.
        Analysis.People.update {instanceId: expId, userId: userId},
          $set: stats

    Meteor._debug("Analysis complete.")

  # Compute the specialization of each real group, both individually and for the group as a whole.
  "cm-compute-group-specialization": ->
    TurkServer.checkAdmin()

    weights = Meteor.call("cm-get-action-weights")

    for world in Analysis.Worlds.find({pseudo: null, synthetic: null}).fetch()
      groupId = world._id
      # Add up weights in each category for each user
      userWeights = {}

      for entry in Logs.find({_groupId: groupId}).fetch()
        userId = entry._userId
        type = Util.logActionType(entry)
        weight = weights[entry.action]

        continue unless weight? and type

        userWeights[userId] ?= { filter: 0, verify: 0, classify: 0, chat: 0 }
        userWeights[userId][type] += weight

      roomIds = ChatRooms.direct.find(_groupId: groupId).map (room) -> room._id
      chatWeight = weights["chat"]

      for chat in ChatMessages.find({room: $in: roomIds}).fetch()
        userId = chat.userId

        userWeights[userId] ?= { filter: 0, verify: 0, classify: 0, chat: 0 }
        userWeights[userId]["chat"] += chatWeight

      spec = []

      # Compute avg individual specialization
      for userId, map of userWeights
        sum = 0
        for type, val of map
          sum += val

        probs = []
        for type, val of map
          probs.push val / sum

        ent = Util.entropy(probs)
        spec.push { wt: sum, ent: ent }

      # Compute group specialization
      groupWeights = _.reduce userWeights, (acc, map) ->
        for type, val of map
          acc[type] = (acc[type] || 0) + val
        return acc
      , {}

      totalWeight = _.reduce groupWeights, (a, v) -> a + v

      groupWeights = (w / totalWeight for k, w of groupWeights)

      avgIndivEntropy = spec.reduce( ((a, v) -> a + (v.wt * v.ent)), 0 ) / totalWeight
      groupEntropy = Util.entropy(groupWeights)

      console.log groupId, world.nominalSize
      console.log avgIndivEntropy, groupEntropy

      Analysis.Worlds.update groupId, $set: { avgIndivEntropy, groupEntropy }

  # Compute performance of pseudo-aggregated groups, as in discussion with Peter.
  "cm-compute-pseudo-performance": ->
    TurkServer.checkAdmin()

    weights = Meteor.call("cm-get-action-weights")

    gsEvents = getGoldStandardEvents()

    for groupSize in [1, 2, 4, 8]
      console.log "Syncing replays of size #{groupSize} groups"

      replays = []

      for world in Analysis.Worlds.find({treated: true, nominalSize: groupSize}).fetch()
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

      Analysis.Worlds.upsert {pseudo: true, treated: false, nominalSize: groupSize},
        $set:
          progress: increments
          wallTime: lastIncrement.wt
          personTime: lastIncrement.mt
          totalEffort: lastIncrement.ef
          partialCreditScore: lastIncrement.ps
          fullCreditScore: lastIncrement.ss

  ###
  Compute synthetic performance of different groups of size 1.

  TODO Current limitations:
  - Only uses groups of size 1 (2 or more are trickier)
  - Assumes all size 1 groups worked for exactly 1 hour / no wall time adj
  - Only uses end state at the moment
  ###
  "cm-compute-synthetic-performance": ->
    TurkServer.checkAdmin()

    weights = Meteor.call("cm-get-action-weights")

    # Remove all previous generated data
    Analysis.Worlds.remove({synthetic: true})

    gsEvents = getGoldStandardEvents()
    singles = Analysis.Worlds.find({treated: true, nominalSize: 1}).fetch()
    maxSamples = 100

    # Form synthetic groups of size 2 up to total - 2
    for cSize in [2..singles.length - 2]
      for i in [1..maxSamples]
        worlds = _.sample(singles, cSize)
        ids = _.map(worlds, (w) -> w._id )

        aggEvents = Events.direct.find({
          _groupId: { $in: ids },
          deleted: { $exists: false },
        }).fetch()

        [partialScore, strictScore] = matchingScore(aggEvents, gsEvents)

        console.log partialScore, strictScore

        Analysis.Worlds.insert
          synthetic: true
          treated: false
          worlds: ids
          personTime: cSize
          totalEffort: worlds.reduce ((acc, w) -> acc + w.totalEffort), 0
          partialCreditScore: partialScore
          fullCreditScore: strictScore

      console.log "Completed #{i} samples of synthesized groups of #{cSize}"
