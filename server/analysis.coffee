# Collections for analysis
AnalysisWorlds = new Meteor.Collection("analysis.worlds")

AnalysisDatastream = new Meteor.Collection("analysis.datastream")
AnalysisEvents = new Meteor.Collection("analysis.events")

# Special groundtruth tag for these instances
TurkServer.ensureTreatmentExists
  name: "groundtruth"

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
    sleep = Meteor._wrapAsync((time, cb) -> Meteor.setTimeout (-> cb undefined), time)
    sleep(2000)

  # Fake treatmeent identifier for this instance to allow admin editing
  # Experiments.upsert(instanceName, $set: { treatments: [ "editable" ]})

  return instance

Meteor.methods
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

  # Get the list of re-mapped tweet IDs in the groups of 16 and 32
  # TODO this can probably just pull from the analysis collections
  "cm-get-group-cooccurences": ->
    TurkServer.checkAdmin()

    expIds = getLargeGroupExpIds()

    console.log "Found #{expIds.length} experiments"

    # Re-map tweet numbers on all non-deleted events
    occurrences = Events.direct.find({
      _groupId: $in: expIds
      deleted: $exists: false
    }).map (event) ->
      _.map event.sources, (source) -> Datastream.direct.findOne(source).num

    tweetText = {}

    Datastream.direct.find({_groupId: expIds[0]}).forEach (e) ->
      tweetText[e.num] = e.text

    return { occurrences, tweetText }

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
