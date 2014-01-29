# Chat
this.ChatRooms = new Meteor.Collection("chatrooms")

# this.ChatUsers (separate file) and ChatMessages do not need to be stuffed into TurkServer
this.ChatMessages = new Meteor.Collection("chatmessages")

# Datastream
this.Datastream = new Meteor.Collection("datastream")

# Docs
this.Documents = new Meteor.Collection("documents")

# Events / Map
this.EventFields = new Meteor.Collection("eventfields") # Also not turkservered.
this.Events = new Meteor.Collection("events")

# Chat and invite notivications
this.Notifications = new Meteor.Collection("notifications") # Not turkservered since each user sees their own

# Group the four main partitioned collections
TurkServer.partitionCollection(ChatRooms)
TurkServer.partitionCollection(Datastream)
TurkServer.partitionCollection(Documents)
TurkServer.partitionCollection(Events, {
  index: { num: 1 }  # Create an index on event sequencing for efficient lookup
})

Meteor.methods
  ###
    Data Methods
  ###
  dataHide: (id) ->
    TurkServer.checkNotAdmin()
    # Can't hide tagged events
    return if not @isSimulation and Datastream.findOne(id)?.events?.length > 0

    Datastream.update id,
      $set: { hidden: true }

    Mapper.events.emit("data-hide") if @isSimulation
    return

  dataLink: (tweetId, eventId) ->
    TurkServer.checkNotAdmin()
    return unless tweetId and eventId

    # Attach this tweet to the event
    Events.update eventId,
      $addToSet: { sources: tweetId }

    # Attach this event to the tweet, unhide if necessary
    Datastream.update tweetId,
      $addToSet: { events: eventId }
      $set: { hidden: false }

    Mapper.events.emit("data-link") if @isSimulation
    return

  dataUnlink: (tweetId, eventId) ->
    TurkServer.checkNotAdmin()
    return unless tweetId and eventId

    Events.update eventId,
      $pull: { sources: tweetId }

    Datastream.update tweetId,
      $pull: { events: eventId }
    return

  ###
    Event Methods
  ###
  createEvent: (eventId, fields) ->
    TurkServer.checkNotAdmin()

    obj = {
      _id: eventId
      sources: []
    # location: undefined
    }

    _.extend(obj, fields)

    # On server, increment number based on highest numbered event
    unless @isSimulation
      maxEventIdx = Events.findOne({}, sort: {num: -1})?.num || 0
      obj.num = maxEventIdx + 1

    Events.insert(obj)

    Mapper.events.emit("event-create") if @isSimulation
    return

  editEvent: (id) ->
    TurkServer.checkNotAdmin()
    userId = Meteor.userId()
    unless userId?
      bootbox.alert("Sorry, you must be logged in to make edits.") if @isSimulation
      return

    event = Events.findOne(id)

    unless event.editor
      Events.update id,
        $set: { editor: userId }
      Mapper.events.emit("event-edit") if @isSimulation
    else if @isSimulation and event.editor isnt userId
      bootbox.alert("Sorry, someone is already editing that event.")

    return

  updateEvent: (id, fields) ->
    TurkServer.checkNotAdmin()
    Events.update id,
      $set: fields

    if @isSimulation
      for key of fields
        break
      Mapper.events.emit("event-update-" + key)

    return

  saveEvent: (id) ->
    Events.update id,
      $unset: { editor: 1 }

    Mapper.events.emit("event-save") if @isSimulation
    return

  voteEvent: (id) ->
    userId = Meteor.userId()
    unless userId
      bootbox.alert("You must be logged in to vote on an event.") if @isSimulation
      return

    Events.update id,
      $addToSet: { votes: userId }
    Mapper.events.emit("event-vote") if @isSimulation
    return

  unvoteEvent: (id) ->
    userId = Meteor.userId()
    unless userId
      bootbox.alert("You must be logged in to vote on an event.") if @isSimulation
      return

    Events.update @_id,
      $pull: { votes: userId }
    return

  deleteEvent: (id) ->
    TurkServer.checkNotAdmin()
    event = Events.findOne(id)

    # Pull all tweet links
    _.each event.sources, (tweetId) ->
      Datastream.update tweetId,
        $pull: { events: id }

    Events.remove(id)
    return

  ###
    Chat Methods
  ###
  createChat: (roomName) ->
    TurkServer.checkNotAdmin()
    ChatRooms.insert
      name: roomName
      users: 0
    Mapper.events.emit("chat-create") if @isSimulation
    return

  # sendChat: does extra stuff on server

  deleteChat: (roomId) ->
    TurkServer.checkNotAdmin()
    if @isSimulation
      # Client stub - do a quick check
      unless ChatRooms.findOne(roomId).users is 0
        bootbox.alert "You can only delete empty chat rooms."
      else
        ChatRooms.remove roomId
    else
      # Server method
      return unless ChatUsers.find(roomId: roomId).count() is 0
      ChatRooms.remove roomId
      # TODO should we delete messages? Or use them for logging...
    return

  ###
    Notifications
  ###

  # inviteChat: does stuff on server

  readNotification: (noteId) ->
    Notifications.update noteId,
      $set: {read: Date.now()}
    return
