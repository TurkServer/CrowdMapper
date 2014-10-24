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

# Centroid of location
# This is approximate cause it's on a sphere, but should be good enough
# https://en.wikipedia.org/wiki/Centroid#Of_a_finite_set_of_points
getCentroid = (events) ->
  location = [0, 0]

  _.each events, (e) ->
    location[0] += e.location[0]
    location[1] += e.location[1]

  location[0] /= events.length
  location[1] /= events.length

  return location

preparePabloInstance = (instanceName, force) ->

  if Experiments.findOne(instanceName)?
    throw new Meteor.Error(403, "aggregated instance already exists") unless force
    # Reuse same tweets that are loaded
    console.log ("removing old event aggregation data")
    Events.direct.remove({_groupId: instanceName})
    instance = TurkServer.Instance.getInstance(instanceName)

  else
    Experiments.upsert(instanceName, $set: {})

    # First run, load new tweets
    instance = TurkServer.Instance.getInstance(instanceName)
    instance.bindOperation ->
      Mapper.loadCSVTweets("PabloPh_UN_cm.csv", 2000)
      console.log("Loaded new tweets")

    # Sleep a moment until all tweets are loaded, before proceeding
    sleep = Meteor.wrapAsync((time, cb) -> Meteor.setTimeout (-> cb undefined), time)
    sleep(2000)

  # Fake treatmeent identifier for this instance to allow admin editing
  # Experiments.upsert(instanceName, $set: { treatments: [ "editable" ]})

  return instance

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

  # Create and populate a world that represents the Pablo data from groups of
  # 16 and 32
  "cm-aggregate-pablo-gt": (force) ->
    TurkServer.checkAdmin()

    instanceName = "groundtruth-pablo"
    instance = preparePabloInstance(instanceName, force)

    expIds = getLargeGroupExpIds()

    console.log "Found #{expIds.length} experiments"

    instance.bindOperation ->
      # Start with all tweets hidden. un-hide them if any group has them
      # hidden or attached
      Datastream.update({}, {
        $set: {hidden: true, events: []}
      }, {multi: true})

    remapSources = (sources) ->
      for source in sources
        num = Datastream.direct.findOne(source).num
        Datastream.direct.findOne({_groupId: instanceName, num})._id

    ###
      Process existing groups as follows:
      - Create all (non-deleted) events referencing the tweet with the same number
      - Re-map sources and events to the new ids
      - Unhide any tweets that are attached or not hidden
    ###

    currentNum = 0

    for expId in expIds
      console.log "Processing #{exp._id} (#{exp.users.length})"

      Events.direct.find({
        _groupId: expId
        deleted: $exists: false
      }, {
        fields: {num: 0, editor: 0}
      }).forEach (event) ->

        # omit the _id field, and transform the sources array
        delete event._id
        event.sources = remapSources(event.sources)
        event.num = ++currentNum

        instance.bindOperation ->
          # Insert the transformed event
          newEventId = Events.insert(event)
          # Push this event on to remapped tweets
          Datastream.update({
            _id: { $in: event.sources }
          }, {
            $addToSet: { events: newEventId }
          }, {multi: true})

      console.log "Done copying events"

      # unhide any tweets that were not hidden or attached
      remainingTweets = Datastream.direct.find({
        _groupId: exp._id,
        hidden: { $exists: false }
      }).map (tweet) -> tweet._id

      Datastream.direct.update({
        _id: $in: remapSources(remainingTweets)
      }, {
        $unset: {hidden: null}
      }, {
        multi: true
      })

    console.log "done"

  # Get the list of re-mapped tweet IDs for completed experiment events
  # TODO this can probably just pull from the analysis collections, which are already re-mapped
  "cm-get-group-cooccurences": ->
    TurkServer.checkAdmin()

    expIds = getGoldStandardExpIds()

    console.log "Found #{expIds.length} experiments"

    # Re-map tweet numbers on all non-deleted events that have fields filled in
    occurrences = Events.direct.find({
      _groupId: $in: expIds
      deleted: $exists: false
      "sources.0": $exists: true
      type: $ne: null
      province: $ne: null
      region: $ne: null
      location: $ne: null
    }).map (event) ->
      _.map event.sources, (source) -> Datastream.direct.findOne(source).num

    console.log "Found #{occurrences.length} completed events"

    tweetText = {}

    Datastream.direct.find({_groupId: expIds[0]}).forEach (e) ->
      tweetText[e.num] = e.text

    return { occurrences, tweetText }

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

  # Build the analysis events and data collection from the experimental data
  "cm-populate-analysis-data": (force) ->
    TurkServer.checkAdmin()

    expIds = getGoldStandardExpIds()
    console.log "Found #{expIds.length} experiments"

    unless force
      throw new Meteor.Error(400, "Events already exist") if AnalysisEvents.find().count() > 0
      throw new Meteor.Error(400, "Datastream already exists") if AnalysisDatastream.find().count() > 0

    AnalysisEvents.remove({})
    AnalysisDatastream.remove({})

    tweetNums = []

    eventCount = 0

    # Re-map tweet IDs to numbers on all non-deleted events
    Events.direct.find({
      _groupId: $in: expIds
      deleted: $exists: false
    }).forEach (event) ->
      # Only take events that are mostly completed
      # with at least one tweet, a type, region, province, and location
      return unless event.sources?.length and event.type?
      return unless event.region? and event.province? and event.location?

      delete event._groupId
      # We keep the _id for reference

      event.sources = _.map event.sources, (source) -> Datastream.direct.findOne(source).num
      tweetNums = _.union(tweetNums, event.sources)

      AnalysisEvents.insert(event)
      eventCount++

    console.log "#{eventCount} completed events for mapping"
    console.log "#{tweetNums.length} unique tweets mapped"

    # Insert a fresh copy of tweets with numbers
    Datastream.direct.find({
      _groupId: expIds[0]
      num: $in: tweetNums
    }).forEach (tweet) ->

      delete tweet._groupId
      delete tweet._id
      delete tweet.events

      AnalysisDatastream.insert(tweet)

    return

  "cm-clustered-pablo-gt": (force) ->
    TurkServer.checkAdmin()

    instanceName = "groundtruth-pablo"
    instance = preparePabloInstance(instanceName, force)

    instance.bindOperation ->
      # Start with all tweets hidden. un-hide tweets in clusters
      Datastream.update({}, {
        $set: {hidden: true, events: []}
      }, {multi: true})

    remapSources = (sources) ->
      for sourceNum in sources
        Datastream.direct.findOne({_groupId: instanceName, num: sourceNum})._id

    clusters = _.uniq AnalysisEvents.find({cluster: $ne: null}).map (e) -> e.cluster

    currentNum = 0

    for c in clusters
      clusterEvents = AnalysisEvents.find({cluster: c}).fetch()
      clusterTweets = AnalysisDatastream.find({cluster: c}).fetch()

      numReports = clusterEvents.length

      console.log """Cluster #{c}:
        #{numReports} reports, #{clusterTweets.length} tweets"""

      event = {}

      worstAgreement = 1.0

      # Take most common type, region, and province
      _.each ["type", "region", "province"], (field) ->
        counts = _.countBy clusterEvents, (e) -> e[field]
        [ best, count ] = _.max _.pairs(counts), _.last

        best = parseInt(best) # Convert it back to an integer

        caption = EventFields.findOne({key: field}).choices[best]
        agreement = count / numReports
        worstAgreement = Math.min(agreement, worstAgreement)

        console.log "#{field} = #{caption} (#{(agreement*100).toFixed(2)}%)"
        event[field] = best

      # Don't record this event if the consensus is pretty much random on any field
      if worstAgreement < 1.0 and worstAgreement < 1/numReports + 1e-6
        console.log "Skipping due to low agreement"
        continue

      if (centroidEvents = _.filter(clusterEvents, (e) ->
          event.region is e.region and event.province is e.province)).length
        event.location = getCentroid(centroidEvents)
        console.log "Computed centroid from #{centroidEvents.length} reports"
      else
        centroidEvents = _.filter(clusterEvents, (e) ->
          event.region is e.region or event.province is e.province)
        event.location = getCentroid(centroidEvents)
        console.log "Computed centroid from #{centroidEvents.length} reports (loose)"

      # Okay, we are inserting this event. Finalize the data.

      event.sources = remapSources(_.map clusterTweets, (t) -> t.num)
      event.num = ++currentNum

      instance.bindOperation ->
        # Insert the transformed event
        newEventId = Events.insert(event)
        # Push this event on to remapped tweets
        Datastream.update({
          _id: { $in: event.sources }
        }, {
          $addToSet: { events: newEventId }
        }, {multi: true})

    return

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
