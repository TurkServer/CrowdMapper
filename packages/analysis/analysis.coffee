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
          wt: replay.wallTime / millisPerHour
          mt: replay.manTime / millisPerHour
          ef: replay.manEffort / millisPerHour
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
        stats.time /= millisPerHour
        stats.effort /= millisPerHour

        # This skips people that aren't in the db.
        Analysis.People.update {instanceId: expId, userId: userId},
          $set: stats

    Meteor._debug("Analysis complete.")

capFirst = (str) -> str.charAt(0).toUpperCase() + str.slice(1);

Meteor.methods
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

      userStats = {}

      ###
        individual specialization features:

        - effort in each subtasks (and fraction)
        - entropy across actions
      ###
      for userId, map of userWeights
        sum = 0
        for type, val of map
          sum += val

        userStats[userId] = {}

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

      totalWeight = _.reduce groupWeights, add, 0

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

      Analysis.Worlds.update groupId, $set: groupStats

      for userId, stats of userStats
        delete stats["effort"] # This is computed elsewhere
        Analysis.People.update {userId, instanceId: groupId}, $set: stats

  # Compute words uttered in chat and equality across group
  "cm-compute-chat-weight": ->
    TurkServer.checkAdmin()

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

  chatWordCount: "number of words uttered in chat"
  chatWordFrac: "fraction of total chat words in group"

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

  g_partialCreditScore: "group score accounting for partial accuracy"
  g_fullCreditScore: "group score rounded to 0-1 based on threshold"
  g_precision: "precision computed from 0-1 score"
  g_recall: "recall computed from 0-1 score"
  g_f1: "F-1 score"

  g_avgIndivEntropy: "weighted average of individual user action entropy"
  g_effortEntropy: "entropy of effort contribution from users"
  g_groupEntropy: "entropy of group actions across categories"
  g_eventContention: "average number of people contributing effort to an event"
  g_eventContentionExVoting: "event contention excluding votes"

  g_chatFrac: "fraction of effort spent on chat"
  g_chatWeight: "effort time spent on chat"
  g_classifyFrac: ""
  g_classifyWeight: ""
  g_filterFrac: ""
  g_filterWeight: ""
  g_verifyFrac: ""
  g_verifyWeight: ""

  g_chatWordCount: "total chat volume in words"
  g_chatWordEntropy: "entropy of chat word volume across users"
}

dataTransform = {
  normalizedEffort: (d) -> d.effort / d.time
  g_effortPerPerson: (d) -> d.g_totalEffort / d.g_personTime
  g_f1: (d) -> 2 * d.g_precision * d.g_recall / (d.g_precision + d.g_recall)
}

Meteor.methods
  "cm-generate-data-csv": ->
    results = []

    Analysis.Worlds.find(
      {pseudo: null, synthetic: null, treated: true},
      { sort: { nominalSize: 1 } }
    ).forEach (w) ->
      groupStats = {}

      for key, desc of dataFields
        if key.slice(0, 2) is "g_"
          groupStats[key] = w[ key.slice(2) ]

      # Compute group transformed states
      for key, f of dataTransform
        if key.slice(0, 2) is "g_"
          groupStats[key] = f(groupStats)

      Analysis.People.find({instanceId: w._id}).forEach (p) ->
        stats = _.extend {}, groupStats

        for key, desc of dataFields
          continue if key.slice(0, 2) is "g_"
          stats[key] = p[key]

        # Compute individual transforms
        for key, f of dataTransform
          unless key.slice(0, 2) is "g_"
            stats[key] = f(stats)

        results.push(stats)

    convert = Meteor.wrapAsync(Npm.require('json2csv'))

    return convert({data: results, fields: (key for key, desc of dataFields)})

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
