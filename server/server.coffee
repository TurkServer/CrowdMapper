###
  TurkServer-ed publications
  All of these publications check for grouping, except notifications
###

# User status and username
Meteor.publish "userStatus", ->
  ###
    The status field below should really be "status.online" to not publish random other status fields
    But we need to leave it at status because otherwise we will be missing fields on the merge.
    https://github.com/meteor/meteor/issues/998
  ###
  Meteor.users.find {}, # All users (in my group)
    fields:
      username: 1
      status: 1

# Publish all events, docs, and events, including deleted - filtering is done on the client
# This means admins can see deleted items easily, and they still work in chat

Meteor.publish "datastream", -> Datastream.find()

Meteor.publish "docs", -> Documents.find()

Meteor.publish "events", -> Events.find()

Meteor.publish 'notifications', ->
  # Only publish unread notifications for this user (in this instance)
  Notifications.find
    user: this.userId
    read: {$exists: false}

###
  Replay publication for admin
  currently sends users, docs, events
  # TODO lots of hacks here. Integrate with TurkServer APIs.
###
class ReplayHandler
  sleep = Meteor._wrapAsync((time, cb) -> Meteor.setTimeout (-> cb undefined), time)

  constructor: (instance) ->
    @exp = Experiments.findOne(instance)
    throw new Error("nonexistent instance") unless @exp

    Meteor._debug("Setting up replay for #{instance}")

    @tempData = new Meteor.Collection(null)
    @tempEvents = new Meteor.Collection(null)

  publishData: (sub) ->
    # Send fake local collection data over the wire
    # We're pretending to do the same thing as with an array of cursors
    Meteor.Collection._publishCursor(@tempData.find(), sub, Datastream._name)
    Meteor.Collection._publishCursor(@tempEvents.find(), sub, Events._name)

    userCursor = Meteor.users.find({ _id: $in: @exp.users},
      {fields: {username: 1}})
    Meteor.Collection._publishCursor(userCursor, sub, "users")

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
        # TODO: in newer data, don't unhide tweets
        event = @tempEvents.findOne(log.eventId)

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

Meteor.publish "replay", (instance) ->
  return [] unless Meteor.users.findOne(@userId).admin

  replay = new ReplayHandler(instance)

  replay.initialize()
  replay.publishData(this)

  this.ready()
  replay.play(30)

  this.onStop -> replay.destroy()

###
  Methods
###

Meteor.methods
  "finishTutorial": ->
    exp = TurkServer.Instance.currentInstance()
    if exp.treatment()?.tutorialEnabled
      exp.teardown()

  "getMapperData": (groupId) ->
    TurkServer.checkAdmin()

    instance =  Experiments.findOne(groupId)

    roomIds = Partitioner.directOperation ->
      ChatRooms.find(_groupId: groupId).map (room) -> room._id

    users = Meteor.users.find(_id: $in: instance.users).fetch()
    logs = Logs.find({_groupId: groupId}, {sort: {_timestamp: 1}}).fetch()
    chat = ChatMessages.find({room: $in: roomIds}, {sort: {timestamp: 1}}).fetch()

    return {instance, users, logs, chat}

  # TODO hack-ass method that needs to be re-implemented in a more generalized way
  "computePayment": (groupId, ratio, actuallyPay) ->
    TurkServer.checkAdmin()

    exp = TurkServer.Instance.getInstance(groupId)
    batch = exp.batch()

    treatmentData = exp.treatment()
    hourlyWage = treatmentData.wage + (ratio * treatmentData.bonus)
    console.log "hourly wage: " + hourlyWage

    millisPerHour = 3600 * 1000

    for userId in exp.users()
      user = Meteor.users.findOne(userId)
      asstId = Assignments.findOne({batchId: batch.batchId, workerId: user.workerId})._id
      asst = TurkServer.Assignment.getAssignment(asstId)
      continue unless asst.isCompleted()

      # Compute wage and make a message here
      instanceData = _.find(asst._data()?.instances, (inst) -> inst.id is groupId)

      totalTime = (instanceData.leaveTime - instanceData.joinTime)
      idleTime = (instanceData.idleTime || 0)
      disconnectedTime = (instanceData.disconnectedTime || 0)

      # TODO Temporary workaround for buggy accounting
      idleTime = 0 if idleTime / millisPerHour > 0.2
      disconnectedTime = 0 if disconnectedTime / millisPerHour > 0.2

      activeTime = totalTime - idleTime - disconnectedTime

      hourlyWageStr = hourlyWage.toFixed(2)
      payment = +(hourlyWage * activeTime / millisPerHour).toFixed(2)

      activeStr = TurkServer.Util.formatMillis(activeTime)
      idleStr = TurkServer.Util.formatMillis(idleTime)
      discStr = TurkServer.Util.formatMillis(disconnectedTime)

      message =
        """Dear #{user.username},

          Thank you very much for participating in the crisis mapping session. We sincerely appreciate your effort and feedback.

          Your team earned an hourly wage of $#{hourlyWageStr}. You participated for #{activeStr}, not including idle time of #{idleStr} and disconnected time of #{discStr}. For your work, you are receiving a bonus of $#{payment.toFixed(2)}.

          Please free to send me a personal message if you have any other questions about the task or your payment.
        """

      console.log message
      throw new Error("The world is about to end") if payment > 11

      if (actuallyPay)
        asst.setPayment(payment)
        asst.payBonus(message)

