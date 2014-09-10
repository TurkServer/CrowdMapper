
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

Meteor.methods
  # Create and populate a world that represents the Pablo data from groups of
  # 16 and 32
  "cm-aggregate-pablo-gt": (force) ->
    TurkServer.checkAdmin()

    instanceName = "groundtruth-pablo"

    if Experiments.findOne(instanceName)?
      throw new Meteor.Error(403, "aggregated instance already exists") unless force?
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

    # Fake identifier for this instance to allow admin editing
    Experiments.upsert(instanceName, $set: { treatments: [ "groundtruth" ]})

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


