###
  Replay publication for admin
  currently sends users, docs, events
  # TODO lots of hacks here. Integrate with TurkServer APIs.
###
class ReplayHandler
  # The earliest experiment for which we changed the behavior of event deleting
  eventDeleteChange = new Date("2014-07-29T15:28:57.242Z")

  sleep = Meteor.wrapAsync((time, cb) -> Meteor.setTimeout (-> cb undefined), time)

  constructor: (instance) ->
    @exp = Experiments.findOne(instance)
    throw new Error("nonexistent instance") unless @exp

    Meteor._debug("Setting up replay for #{instance}")

    # Do old behavior?
    if @exp.startTime < eventDeleteChange
      @pullDeletedEventTweets = true
      Meteor._debug("Using old event deletion behavior.")

    @tempUsers = new Mongo.Collection(null)
    @tempData = new Mongo.Collection(null)
    @tempEvents = new Mongo.Collection(null)

  publishData: (sub) ->
    # Send fake local collection data over the wire
    # We're pretending to do the same thing as with an array of cursors
    Mongo.Collection._publishCursor(@tempData.find(), sub, Datastream._name)
    Mongo.Collection._publishCursor(@tempEvents.find(), sub, Events._name)

    # This is cool, we get to track users for the replay as well as for the analysis
    Mongo.Collection._publishCursor(@tempUsers.find(), sub, "users")

    sub.ready()

  initialize: (actionWeights) ->
    @actionWeights = actionWeights

    # Load all the initial tweet data in, without any state
    tempData = @tempData
    Partitioner.bindGroup @exp._id, ->
      Datastream.find({}, {fields: {num:1, text:1}}).forEach (data) ->
        tempData.insert(data)

    # Get logs and chat for analysis
    @logs = Logs.find({_groupId: @exp._id}, {sort: {_timestamp: 1}}).fetch()

    roomIds = ChatRooms.direct.find(_groupId: @exp._id).map (room) -> room._id
    @chat = ChatMessages.find({room: {$in: roomIds}}, {sort: {timestamp: 1}}).fetch()

    # Set up counters
    @eventCount = 0

    # Log indices
    @li = 0
    @ci = 0

    # Performance metrics
    @wallTime = 0
    @manTime = 0
    @manEffort = 0

    @userEffort = {}

  ensureUserActive: (userId) ->
    result = @tempUsers.upsert userId,
      $set: { "status.online": true, "status.idle": false }

    # If inserting this user for the first time, look up their username
    if result.insertedId?
      @tempUsers.update userId,
        $set: username: Meteor.users.findOne(userId).username

  activeUsers: ->
    # count online, non-idle users
    @tempUsers.find({
      "status.online": true
      "status.idle": $ne: true
    }).map (u) -> u._id

  nextEventTime: ->
    nextLog = @logs[@li]
    nextChat = @chat[@ci]

    return unless nextLog? or nextChat?

    return Math.min(
        nextLog?._timestamp || Date.now(),
        nextChat?.timestamp || Date.now() )

  # Process and record the next log/chat event.
  processNext: ->
    nextLog = @logs[@li]
    nextChat = @chat[@ci]

    lastWallTime = @wallTime
    activeUsers = @activeUsers()

    if nextLog?._timestamp < ( nextChat?.timestamp || Date.now() )
      @li++
      @processEvent(nextLog)
    else if nextChat? # next event for this user is chat
      @ci++
      @processChat(nextChat)
    else
      throw new Error("Nothing left to process")

    # Record number of people active during this period
    tickTime = @wallTime - lastWallTime

    @recordTime(activeUsers, tickTime)

  processEvent: (log) =>
    @wallTime = log._timestamp - @exp.startTime

    if log._meta
      switch log._meta
        # May be inserting a new user for connected / active (esp when starting)
        when "connected", "active"
          @ensureUserActive(log._userId)
        when "idle"
          @tempUsers.update log._userId,
            $set: { "status.idle": true }
        when "disconnected"
          @tempEvents.update { editor: log._userId },
            $unset: { editor: null }
          # Remove any online/idle status
          @tempUsers.update log._userId,
            $unset: { status: null }
        when "created", "initialized"
        else
          Meteor._debug("Don't know what to do with ", log)
          throw new Error()
      return

    switch log.action
    # Stuff we don't know what to do with yet
      when "data-hide"
        @tempData.update log.dataId,
          $set: hidden: true
      when "data-link"
        @tempEvents.update log.eventId,
          $addToSet: { sources: log.dataId }
        @tempData.update log.dataId,
          $addToSet: { events: log.eventId }
      when "data-move"
        @tempEvents.update log.fromEventId,
          $pull: { sources: log.dataId }
        @tempData.update log.dataId,
          $addToSet: { events: log.toEventId }
        @tempData.update log.dataId,
          $pull: { events: log.fromEventId }
        @tempEvents.update log.toEventId,
          $addToSet: { sources: log.dataId }
      when "data-unlink"
        @tempData.update log.dataId,
          $pull: { events: log.eventId }
          $set: { hidden: true }
        @tempEvents.update log.eventId,
          $pull: { sources: log.dataId }
      when "event-create"
        @tempEvents.insert
          _id: log.eventId
          sources: []
          num: ++@eventCount # TODO is this accurate?
      when "event-edit"
        @tempEvents.update log.eventId,
          $set: editor: log._userId
      when "event-update"
        @tempEvents.update log.eventId,
          $set: log.fields
      when "event-unmap"
        @tempEvents.update log.eventId,
          $unset: { location: null }
      when "event-save"
        @tempEvents.update log.eventId,
          $unset: { editor: null }
      when "event-vote"
        @tempEvents.update log.eventId,
          $addToSet: { votes: log._userId }
      when "event-unvote"
        @tempEvents.update log.eventId,
          $pull: { votes: log._userId }
      when "event-delete"
        event = @tempEvents.findOne(log.eventId)

        if @pullDeletedEventTweets
          # Only unhide tweets in old data
          _.each event.sources, (dataId) =>
            @tempData.update dataId,
              $pull: { events: log.eventId }

        @tempEvents.update log.eventId,
          $set: { deleted: true }
      when "document-create", "document-rename", "document-delete", "document-open"
        null
      when "chat-create", "chat-rename", "room-enter", "chat-delete" then null
      else
        Meteor._debug("Don't know what to do with ", log)
        throw new Error()

    # If user did an action, make sure they are not counted as inactive
    # Some bookkeeping may have been off during the experiment
    @ensureUserActive(log._userId)

    @recordEffort(log._userId, log.action) if @actionWeights?
    return

  processChat: (chat) ->
    @wallTime = chat.timestamp - @exp.startTime

    @recordEffort(chat.userId, "chat") if @actionWeights?

  recordEffort: (userId, action) ->
    weight = @actionWeights[action] || 0

    @manEffort += weight

    # Initialize user effort if missing
    @userEffort[userId] ?= { effort: 0, time: 0 }
    @userEffort[userId].effort += weight

  recordTime: (userIds, time) ->
    @manTime += userIds.length * time

    # TODO this is somewhat inefficient, but I don't see a correct way to do
    # it otherwise, because replay is also correcting for possible errors in
    # recording the task.
    for userId in userIds
      @userEffort[userId] ?= { effort: 0, time: 0 }
      @userEffort[userId].time += time

    return

  play: (rate) ->
    start = new Date

    # Schedule stuff for future going.
    Meteor.defer =>
      while (time = @nextEventTime())?
        scheduled = (time - @exp.startTime)/rate - (new Date() - start)
        sleep(scheduled) if scheduled > 0
        # Don't try to process stuff if collections got nulled out
        break if @destroyed
        @processNext()

      Meteor._debug "Replay finished"
      @printStats()

  printStats: ->
    wallTimeMins = (@wallTime / 60000).toFixed(2)
    manTimeMins = (@manTime / 60000).toFixed(2)
    manEffortMins = (@manEffort / 60000).toFixed(2)

    Meteor._debug "#{@exp._id}: wall time #{wallTimeMins} min, man time #{manTimeMins} min, effort #{manEffortMins} min"

  destroy: ->
    @destroyed = true
    Meteor._debug("Stopping replay")
    # Does this actually clean stuff? who cares.
    @tempData = null
    @tempEvents = null

Meteor.publish "replay", (instance, speed) ->
  return [] unless Meteor.users.findOne(@userId)?.admin

  replay = new ReplayHandler(instance)

  replay.initialize()
  replay.publishData(this)

  this.ready()

  speed = Math.min(30, Math.max(1, speed))
  Meteor._debug("Starting replay at #{speed}x speed")
  replay.play(speed)

  this.onStop -> replay.destroy()
