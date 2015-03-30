fs = Npm.require('fs');

# Special groundtruth tag for these instances
TurkServer.ensureTreatmentExists
  name: "groundtruth"

# Treatment tag added to enable admin editing of an instance
TurkServer.ensureTreatmentExists
  name: "editable"

getRecruitingBatchId = -> Batches.findOne({name: "recruitment"})._id
getExperimentBatchId = -> Batches.findOne({name: "group sizes redux"})._id

millisPerHour = 3600 * 1000

add = (x, y) -> x + y

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
  return Experiments.find({
    batchId: getExperimentBatchId()
    treatments: $in: [ "group_16", "group_32" ]
    users: $exists: true
  }).map (e) -> e._id

getGoldStandardExpIds = ->
  # Get the experiments that we will use to generate the gold standard
  # This includes ignored treatment groups, but not buffer groups
  return Experiments.find({
    batchId: getExperimentBatchId()
    treatments:
      $in: [
        "group_1", "group_2", "group_4", "group_8", "group_16", "group_32"
      ]
    users: $exists: true
  }).map (e) -> e._id

getAllExpIds = ->
  # Get all crisis mapping experiments that had users join
  return Experiments.find({
    batchId: getExperimentBatchId()
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
    # Remove all user and world stats (not weights)
    Analysis.Stats.remove({instanceId: {$exists: true}})
    Analysis.Stats.remove({userId: {$exists: true}})

    worlds = 0
    people = 0
    dropouts = 0

    for expId in getAllExpIds()
      exp = Experiments.findOne(expId)

      # Ignore experiments where no one submitted (mostly groups of 1)
      exp.completed = Assignments.findOne({
        "instances.id": exp._id
        "status": "completed"
      })?

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

        person = {
          instanceId: exp._id
          userId: userId
          treated: exp.treated
          groupSize: exp.nominalSize
        }

        # TODO put this into a TurkServer API
        if Assignments.findOne({
          workerId: user.workerId
          batchId: exp.batchId
          submitTime: $exists: true
        })?
          person.dropped = false
        else
          person.dropped = true
          dropouts++

        Analysis.People.insert(person)
        people++

    console.log "Recorded #{worlds} instances, #{people} people, #{dropouts} dropouts"

countWords = (str) -> str.match(/(\w+)/g)?.length || 0

Meteor.methods
  # Add user metadata to individual records such as age, gender, and tutorial
  # time and response length
  "cm-compute-user-metadata": ->
    TurkServer.checkAdmin()

    recruitingBatchId = getRecruitingBatchId()
    experimentBatchId = getExperimentBatchId()

    Analysis.People.find().forEach (p, i) ->
      # Find completed tutorial record for this user
      workerId = Meteor.users.findOne(p.userId).workerId

      tutorialAsst = Assignments.findOne({
        batchId: recruitingBatchId
        workerId,
        submitTime: {$exists: true}
      }, {sort: submitTime: -1 })

      tutorialInstanceId = tutorialAsst.instances[0].id
      tutorialInstance = TurkServer.Instance.getInstance(tutorialInstanceId)

      tutorialWords = 0
      for field, str of tutorialAsst.exitdata
        tutorialWords += countWords(str)

      tutorialMins = tutorialInstance.getDuration() / 60000

      experimentAsst = Assignments.findOne({
        batchId: experimentBatchId
        workerId,
        submitTime: {$exists: true}
      })

      exitSurveyWords = 0

      if experimentAsst? # may be dropout
        for field in [ "approach", "specialize", "teamwork", "workwith", "leadership", "misc" ]
          exitSurveyWords += countWords(experimentAsst.exitdata[field])

      Analysis.People.update {instanceId: p.instanceId, userId: p.userId},
        $set: {
          tutorialWords,
          tutorialMins,
          exitSurveyWords,
          age: experimentAsst?.exitdata.age || null,
          gender: experimentAsst?.exitdata.gender || null,
        }

    return

  "cm-compute-group-metadata": ->
    TurkServer.checkAdmin()

    # Number of females out of number of total users, excluding dropouts

    Analysis.Worlds.find({pseudo: null, synthetic: null}).forEach (world) ->
      numFemale = Analysis.People.find({
        instanceId: world._id,
        gender: "female",
        dropped: false
      }).count()

      # XXX do not use nominalSize here
      numTotal = Analysis.People.find({
        instanceId: world._id,
        dropped: false
      }).count()

      Analysis.Worlds.update world._id, $set: {
        fracFemale: numFemale / numTotal
      }

    return

  "cm-get-action-weights": (recompute) ->
    TurkServer.checkAdmin()

    if recompute or not (weights = Analysis.Stats.findOne("actionWeights")?.weights)

      unless Analysis.Worlds.findOne()?
        console.log("No experiments specified for computing weights; grabbing some")
        Meteor.call("cm-populate-analysis-worlds")

      weightArrs = {}
      skipped = 0
      included = 0

      batchId = getExperimentBatchId()
      # Compute weights just over treated groups.
      expIds = Analysis.Worlds.find({treated: true}).map (e) -> e._id

      for expId in expIds
        exp = Experiments.findOne(expId)

        # Run full replay for this experiment
        replay = new ReplayHandler(expId)
        replay.initialize()

        replay.processNext() while replay.nextEventTime()?

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

          userWeights = replay.actionTimeArrs[userId]

          for actionType, actionWeights of userWeights
            weightArrs[actionType] ?= []
            weightArrs[actionType] = weightArrs[actionType].concat(actionWeights)

      # Compute average weight for each action
      weights = {}

      for k, v of weightArrs
        weights[k] = _.reduce(v, add, 0 ) / v.length

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

# Compute the specialization of each real group, both individually and for the group as a whole.
computeGroupStats = (replay) ->
  weights = replay.actionWeights

  userWeights = {}

  # Compute total weights per action type across all users
  # This array just has number of actions, which we weight equally
  for userId, map of replay.actionTimeArrs
    for action, arr of map

      type = Util.actionCategory(action)
      weight = weights[action]

      continue unless type? # Skip null (ignored) types
      if type != null and !weight?
        throw new Meteor.Error(500, "#{action} (#{type}) has no weight")

      userWeights[userId] ?= { filter: 0, verify: 0, classify: 0, chat: 0 }
      userWeights[userId][type] += weight * arr.length

  userStats = {}
  ###
    individual specialization features:

    - effort in each subtasks (and fraction)
    - entropy across actions
  ###
  for userId, map of userWeights
    # Add up all action weights of this user
    sum = 0
    for type, val of map
      sum += val

    userStats[userId] = {}

    # Compute weight and normalized fraction for this user
    probs = []
    for type, val of map
      userStats[userId][type + "Weight"] = val / millisPerHour
      prob = val / sum
      userStats[userId][type + "Frac"] = prob
      probs.push(prob)

    userStats[userId].effort = sum
    userStats[userId].entropy = Util.entropy(probs)

  # Compute group specs
  groupWeights = _.reduce userWeights, (acc, map) ->
    for type, val of map
      acc[type] = (acc[type] || 0) + val
    return acc
  , {}

  totalWeight = _.reduce(groupWeights, add, 0)

  ###
    group specialization features

    - effort across each subtask (and fraction)
    - entropy across subtasks
    - average individual entropy
    - entropy across individuals
  ###
  groupStats = {}
  groupProbs = []

  for type, weight of groupWeights
    groupStats[type + "Weight"] = weight / millisPerHour
    prob = weight / totalWeight
    groupStats[type + "Frac"] = prob
    groupProbs.push(prob)

  userEffortProbs = []

  # individual effort as fraction of group (and per category)
  for userId, stats of userStats
    frac = stats.effort / totalWeight
    userStats[userId]["groupEffortFrac"] = frac
    userEffortProbs.push(frac)

    for type, weight of groupWeights
      # might be NaN, i.e. no chat in a 1 person group
      userStats[userId]["group" + capFirst(type) + "Frac"] =
        (stats[type + "Weight"] / groupStats[type + "Weight"]) || 0

  groupStats.effortEntropy = Util.entropy( userEffortProbs )

  groupStats.avgIndivEntropy =
    _.reduce(userStats, ((a, v) -> a + (v.effort * v.entropy)), 0 ) / totalWeight

  groupStats.groupEntropy =
    Util.entropy(groupProbs)

  return [groupStats, userStats]

saveStats = (replay, expId, gsEvents) ->
  # Compute partial and strict scores
  currentEvents = replay.tempEvents.find({deleted: {$exists: false}})
  eventCount = currentEvents.count()

  [fractionalScore, binaryScore] = matchingScore(currentEvents, gsEvents)

  precision = if eventCount > 0 then binaryScore / eventCount else 0
  recall = binaryScore / gsEvents.length

  wallTime = replay.wallTime / millisPerHour
  personTime = replay.manTime / millisPerHour
  totalEffort = replay.manEffort / millisPerHour

  # Grab specialization stats
  [groupStats, userStats] = computeGroupStats(replay)

  # Combine performance and specialization stats
  _.extend(groupStats, {
    personTime,
    totalEffort,
    fractionalScore,
    binaryScore,
    precision,
    recall
  })

  Analysis.Stats.upsert { instanceId: expId, wallTime },
    $set: groupStats

  # Save the performance for each user
  for userId, stats of replay.userEffort
    # Combine performance and spec stats
    uStats = _.extend({}, stats, userStats[userId])

    # Normalize computed time and effort
    uStats.time /= millisPerHour
    uStats.effort /= millisPerHour

    # Stick in experiment wall time here
    Analysis.Stats.upsert {userId: userId, wallTime},
      $set: uStats

computeReplayStats = (expId, weights, gsEvents, targets, increments=true) ->
  replay = new ReplayHandler(expId)
  replay.initialize(weights)

  # Save stats of 0 zeroes at time 0
  saveStats(replay, expId, gsEvents)

  while replay.nextEventTime()?
    # Compute parameters every 5 wall-minutes or 15 man-minutes, whichever is smaller
    # Or if we have a target we want to hit
    nextWallTimeTarget =
      targets.wallTime[_.sortedIndex(targets.wallTime, replay.wallTime / millisPerHour)] || 100
    nextManTimeTarget =
      targets.manTime[_.sortedIndex(targets.manTime, replay.manTime / millisPerHour)] || 100
    nextEffortTimeTarget =
      targets.manEffort[_.sortedIndex(targets.manEffort, replay.manEffort / millisPerHour)] || 100

    targetWallTime = nextWallTimeTarget * millisPerHour
    targetManTime = nextManTimeTarget * millisPerHour
    targetEffortTime = nextEffortTimeTarget * millisPerHour

    # Compute smaller increments along the way?
    if increments
      targetWallTime = Math.min(replay.wallTime + 5 * 60 * 1000, targetWallTime)
      targetManTime = Math.min(replay.manTime + 15 * 60 * 1000, targetManTime)

    try
      while replay.wallTime < targetWallTime &&
      replay.manTime < targetManTime &&
      replay.manEffort < targetEffortTime
        # This will throw an error if it runs out; giving us one final point
        replay.processNext()
    catch e

    replay.printStats()
    saveStats(replay, expId, gsEvents)

  replay.printStats()

Meteor.methods
  # Compute group performance and effort over time for experiment worlds.
  "cm-compute-group-performance": ->
    TurkServer.checkAdmin()

    weights = Meteor.call("cm-get-action-weights")

    gsEvents = getGoldStandardEvents()

    for world in Analysis.Worlds.find({pseudo: null, synthetic: null}).fetch()
      # Scores we definitely want values for, if possible
      targets = {
        manEffort: [ 1.0, 2.0, 3.0 ]
        manTime: [ 1.0, 2.0, 3.0 ]
        wallTime: [ 0.25, 0.5, 0.75, 1.0 ]
      }

      expId = world._id

      computeReplayStats(expId, weights, gsEvents, targets)

    Meteor._debug("Analysis complete.")

  # Same as above, but divide groups up by quadrants according to man-time and
  # do this only for completed groups with sufficient wall time
  # XXX must run this after the method above!
  "cm-compute-group-quadrants": ->
    TurkServer.checkAdmin()

    weights = Meteor.call("cm-get-action-weights")
    gsEvents = getGoldStandardEvents()

    for world in Analysis.Worlds.find({completed: true}).fetch()
      expId = world._id

      finalStats = Analysis.Stats.findOne({instanceId: expId}, {sort: {wallTime: -1}})

      if finalStats.wallTime < 0.75
        console.log "#{expId} has less than 45 minutes wall time; skipping"
        continue

      targets = {
        manEffort: []
        manTime: [ finalStats.personTime * 0.25,
                   finalStats.personTime * 0.5,
                   finalStats.personTime * 0.75,
        ]
        wallTime: []
      }

      computeReplayStats(expId, weights, gsEvents, targets, false)

    Meteor._debug("Analysis complete.")

capFirst = (str) -> str.charAt(0).toUpperCase() + str.slice(1)

Meteor.methods
  # Compute words uttered in chat and equality across group
  "cm-compute-chat-weight": ->
    TurkServer.checkAdmin()

    throw new Meteor.Error(500, "Implmentation needs updating")

    Analysis.Worlds.find({pseudo: null, synthetic: null}).forEach (world) ->
      groupId = world._id

      roomIds = ChatRooms.direct.find(_groupId: groupId).map (room) -> room._id

      userWords = {}

      for chat in ChatMessages.find({room: $in: roomIds}).fetch()
        userId = chat.userId
        userWords[userId] ?= 0
        userWords[userId] += countWords(chat.text)

      chatVolume = _.reduce(userWords, add, 0)
      chatEntropy = Util.entropy( (words / chatVolume for userId, words of userWords) )

      Analysis.Worlds.update groupId, $set:
        chatWordCount: chatVolume
        chatWordEntropy: chatEntropy

      for userId in world.users
        words = userWords[userId] || 0
        wordFrac = (words / chatVolume) || 0

        Analysis.People.update {userId, instanceId: groupId}, $set:
          chatWordCount: words
          chatWordFrac: wordFrac

getEventContention = (logs, weights, excludeVotes = false) ->

  events = {}

  for entry in logs
    switch entry.action
      when "data-link", "data-unlink"
        eventId = entry.eventId
      when "data-move"
        eventId = entry.toEventId
      when "event-create"
        eventId = entry.eventId
      when "event-update"
        eventId = entry.eventId
      when "event-vote" and !excludeVotes
        eventId = entry.eventId
      else continue

    userId = entry._userId

    events[eventId] ?= {}

    events[eventId][userId] ?= 0
    events[eventId][userId] += weights[entry.action]

  # Calculate entropy across events
  contention = []

  for event, map of events
    eventEffort = _.reduce(map, add, 0)
    eventEntropy = Util.entropy( (eff / eventEffort for userId, eff of map) )
    contention.push Math.pow(2, eventEntropy)

  # Return average contention
  return 0 if contention.length is 0
  return _.reduce(contention, add, 0) / contention.length

Meteor.methods
  "cm-compute-event-contention": ->
    TurkServer.checkAdmin()

    throw new Meteor.Error(500, "Implmentation needs updating")

    weights = Meteor.call("cm-get-action-weights")

    Analysis.Worlds.find({pseudo: null, synthetic: null}).forEach (world) ->
      groupId = world._id
      actionLogs = Logs.find({_groupId: groupId}).fetch()

      eventContention = getEventContention actionLogs, weights
      eventContentionExVoting = getEventContention actionLogs, weights, true

      Analysis.Worlds.update groupId,
        $set: {
          eventContention,
          eventContentionExVoting
        }

dataFields = {
  age: "self-reported participant age"
  gender: "self-reported participant gender"
  instanceId: "ID of the containing experiment group"
  dropped: "whether this user dropped out during the experiment"

  tutorialMins: "Minutes spent to complete tutorial"
  tutorialWords: "Words typed into tutorial exit survey"
  exitSurveyWords: "Number of words typed in exit survey"

  effort: "total effort-time from this user"
  entropy: "entropy across different action categories"
  time: "actual active time of the user"
  normalizedEffort: "effort/time"

  chatFrac: "fraction of user effort on chat"
  chatWeight: "effort-time spent on chat"
  classifyFrac: ""
  classifyWeight: ""
  filterFrac: ""
  filterWeight: ""
  verifyFrac: ""
  verifyWeight: ""

  # chatWordCount: "number of words uttered in chat"
  # chatWordFrac: "fraction of total chat words in group"

  groupEffortFrac: "fraction of this user's effort of group total"
  groupChatFrac: "fraction of this user's chat effort weight of group total"
  groupClassifyFrac: ""
  groupFilterFrac: ""
  groupVerifyFrac: ""

  # Group attributes
  g_nominalSize: "Nominal size of treatment group"
  g_wallTime: "wall time from first joiner to end of experiment"
  g_fracFemale: "percentage of females in the group"

  g_personTime: "person-hours spent by the group"
  g_totalEffort: "effort-hours spent by the group"
  g_effortPerPerson: "totalEffort / personTime"

  g_fractionalScore: "group score accounting for partial accuracy"
  g_binaryScore: "group score rounded to 0-1 based on threshold"
  g_precision: "precision computed from 0-1 score"
  g_recall: "recall computed from 0-1 score"
  g_f1: "F-1 score"

  g_avgIndivEntropy: "weighted average of individual user action entropy"
  g_effortEntropy: "entropy of effort contribution from users"
  g_groupEntropy: "entropy of group actions across categories"
  # g_eventContention: "average number of people contributing effort to an event"
  # g_eventContentionExVoting: "event contention excluding votes"

  g_chatFrac: "fraction of effort spent on chat"
  g_chatWeight: "effort time spent on chat"
  g_classifyFrac: ""
  g_classifyWeight: ""
  g_filterFrac: ""
  g_filterWeight: ""
  g_verifyFrac: ""
  g_verifyWeight: ""

  # g_chatWordCount: "total chat volume in words"
  # g_chatWordEntropy: "entropy of chat word volume across users"
}

dataTransform = {
  normalizedEffort: (d) -> d.effort / d.time
  g_effortPerPerson: (d) -> d.g_totalEffort / d.g_personTime
  g_f1: (d) -> 2 * d.g_precision * d.g_recall / (d.g_precision + d.g_recall)
}

json2csv = Meteor.wrapAsync(Npm.require('json2csv'))

Meteor.methods
  "cm-generate-data-csv": (type) ->
    getKey = switch type
      when "3/4"
        (worldId) ->
          world = Analysis.Worlds.findOne(worldId)

          maxPersonTime = Analysis.Stats.findOne({instanceId: worldId},
            {sort: {wallTime: -1}}).personTime
          targetPersonTime = maxPersonTime * 0.75
          # Find minimum person time above the 3/4 number
          slice = Analysis.Stats.findOne({
              instanceId: worldId,
              personTime: {$gte: targetPersonTime}
            }, {sort: {wallTime: 1}})

          error = Math.abs((slice.personTime - targetPersonTime) / targetPersonTime)

          if world.completed == false
            return null

          # Should small difference (if quadration was run)
          if world.nominalSize > 1 and error > 0.05 or error > 0.13
            throw new Meteor.Error(500, "Couldn't find accurate slice time for #{worldId}: target is #{targetPersonTime} but closest above is #{slice.personTime}")
          return slice.wallTime

      when "eff1"
        (worldId) ->
          slice = Analysis.Stats.findOne({
            instanceId: worldId,
            totalEffort: {$gte: 1.0}
          }, {sort: {wallTime: 1}})
          return slice && slice.wallTime || null

      when "eff3"
        (worldId) ->
          slice = Analysis.Stats.findOne({
            instanceId: worldId,
            totalEffort: {$gte: 3.0}
          }, {sort: {wallTime: 1}})
          return slice && slice.wallTime || null

      else
        (worldId) -> Analysis.Stats.findOne({instanceId: worldId},
          {sort: {wallTime: -1}}).wallTime

    results = []

    Analysis.Worlds.find(
      {pseudo: null, synthetic: null, treated: true},
      { sort: { nominalSize: 1 } }
    ).forEach (w) ->

      wallTimeKey = getKey(w._id)

      unless wallTimeKey?
        console.log "Skipping #{w._id}"
        return

      # Grab slice data for the group
      groupSlice = Analysis.Stats.findOne({instanceId: w._id, wallTime: wallTimeKey})

      groupStats = {}

      for key, desc of dataFields
        if key.slice(0, 2) is "g_"
          groupKey = key.slice(2)
          # Look in either the top-level field or the slice
          groupStats[key] = w[ groupKey ] || groupSlice[ groupKey ]

      # Compute group transformed states
      for key, f of dataTransform
        if key.slice(0, 2) is "g_"
          groupStats[key] = f(groupStats)

      Analysis.People.find({instanceId: w._id}).forEach (p) ->
        stats = _.extend {}, groupStats

        # Grab slice data for the person
        personSlice = Analysis.Stats.findOne({userId: p.userId, wallTime: wallTimeKey})

        unless personSlice?
          console.log "#{p.userId} did not exist at this slice; skipping"
          return

        for key, desc of dataFields
          continue if key.slice(0, 2) is "g_"
          # Look in both places
          stats[key] = p[key] || personSlice[key]

        # Compute individual transforms
        for key, f of dataTransform
          unless key.slice(0, 2) is "g_"
            stats[key] = f(stats)

        results.push(stats)

    return json2csv({data: results, fields: (key for key, desc of dataFields)})

  "cm-generate-effort-quadrants": ->
    TurkServer.checkAdmin()

    results = []

    Analysis.Worlds.find(
      {pseudo: null, synthetic: null, treated: true},
      { sort: { nominalSize: 1 } }
    ).forEach (w) ->

      finalSlice = Analysis.Stats.findOne({instanceId: w._id},
        {sort: {wallTime: -1}})

      maxPersonTime = finalSlice.personTime

      targets = [0.25, 0.5, 0.75].map (frac) ->
        Analysis.Stats.findOne({
          instanceId: w._id,
          personTime: {$gte: maxPersonTime * frac}
        }, {sort: {wallTime: 1}}).wallTime

      targets.push( finalSlice.wallTime )

      # console.log w._id, targets

      # For each person in the group, compute normalized effort in the buckets
      Analysis.People.find({instanceId: w._id}).forEach (p) ->

        if p.dropped
          console.log "#{p.userId} dropped out; skipping"
          return

        accruedEffort = 0
        accruedTime = 0
        q = 0

        for wallTimeTarget in targets
          q++
          personSlice = Analysis.Stats.findOne({userId: p.userId, wallTime: wallTimeTarget})

          unless personSlice?
            # This will skip the person for all later slices
            console.log "#{p.userId} did not exist in early slices; skipping"
            return

          nEff = (personSlice.effort - accruedEffort) / (personSlice.time - accruedTime)

          results.push {
            instanceId: w._id
            userId: p.userId
            g_nominalSize: w.nominalSize
            quadrant: q
            normalizedEffort: nEff
          }

          # Set effort to new value
          accruedEffort = personSlice.effort
          accruedTime = personSlice.time

    return json2csv({
      data: results,
      fields: ["instanceId", "userId", "g_nominalSize", "quadrant", "normalizedEffort"]
    })


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
          wt: totalWallTime / millisPerHour
          mt: totalManTime / millisPerHour
          ef: manEffort / millisPerHour
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
