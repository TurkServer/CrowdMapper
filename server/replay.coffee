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

    @tempData = new Mongo.Collection(null)
    @tempEvents = new Mongo.Collection(null)

  publishData: (sub) ->
    # Send fake local collection data over the wire
    # We're pretending to do the same thing as with an array of cursors
    Mongo.Collection._publishCursor(@tempData.find(), sub, Datastream._name)
    Mongo.Collection._publishCursor(@tempEvents.find(), sub, Events._name)

    userCursor = Meteor.users.find({ _id: $in: @exp.users},
      {fields: {username: 1}})
    Mongo.Collection._publishCursor(userCursor, sub, "users")

  initialize: ->
    tempData = @tempData
    # Load all the fake data in
    Partitioner.bindGroup @exp._id, ->
      Datastream.find({}, {fields: {num:1, text:1}}).forEach (data) ->
        tempData.insert(data)

  play: (rate) ->
    @rate = rate

    @start = new Date
    @eventCount = 0

    replay = this
    instance = @exp._id

    # Schedule stuff for future going.
    Meteor.defer ->
      try
        Logs.find({_groupId: instance}, {sort: {_timestamp: 1}}).forEach replay.processEvent
        Meteor._debug "Replay finished"
      catch e
        Meteor._debug "Replay stopped"

  processEvent: (log) =>
    throw new Error() if @destroyed

    if log._meta
      switch log._meta
        when "disconnect"
          @tempEvents.update { editor: log._userId },
            $unset: { editor: null }
      return

    scheduled = (log._timestamp - @exp.startTime)/@rate - (new Date - @start)
    sleep(scheduled) if scheduled > 0

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
    return

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
