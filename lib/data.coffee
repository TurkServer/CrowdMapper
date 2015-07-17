# Chat
this.ChatRooms = new Mongo.Collection("chatrooms")

# this.ChatUsers (separate file) and ChatMessages do not need to be stuffed into TurkServer
this.ChatMessages = new Mongo.Collection("chatmessages")

# Datastream
this.Datastream = new Mongo.Collection("datastream")

# Docs
this.Documents = new Mongo.Collection("documents")

# Events / Map
this.EventFields = new Mongo.Collection("eventfields") # Also not turkservered.
this.Events = new Mongo.Collection("events")

# Chat and invite notivications
this.Notifications = new Mongo.Collection("notifications") # Not turkservered since each user sees their own

# Group the four main partitioned collections
TurkServer.partitionCollection(ChatRooms)
TurkServer.partitionCollection(Datastream, {
  index: { hidden: 1 } # Partitioning on num won't help anyway as it is sorted on client
})
TurkServer.partitionCollection(Documents)
TurkServer.partitionCollection(Events, {
  index: { num: 1 }  # Create an index on event sequencing for efficient lookup
})
###
  We want to be able to do bulk read operations for users (targets) for a given room.
###
TurkServer.partitionCollection(Notifications, {
  index: {
    user: 1
    room: 1
    read: 1
  }
})

# Admin cannot edit unless it is specially enabled
checkPermissions = ->
  # Don't bother checking treatment unless admin
  return unless TurkServer.isAdmin()
  treatments = TurkServer.treatment()?.treatments || []
  unless treatments.indexOf("editable") >= 0
    throw new Meteor.Error(403, "Can't edit as admin")

Meteor.methods
  ###
    Data Methods
  ###
  dataInsert: (url) ->
    checkPermissions()

    maxEventIdx = Datastream.findOne({}, sort: {num: -1})?.num || 0
    num = maxEventIdx + 1

    Datastream.insert({num, url})

    return

  dataHide: (tweetId) ->
    checkPermissions()
    check(tweetId, String)

    # Can't hide tagged events
    return if not @isSimulation and Datastream.findOne(tweetId)?.events?.length > 0

    Datastream.update tweetId,
      $set: { hidden: true }

    if @isSimulation
      Mapper.events.emit("data-hide")
    else
      @unblock()
      TurkServer.log
        action: "data-hide"
        dataId: tweetId

    return

  # TODO currently only used by admin, adjust logging if enabled for users
  dataUnhide: (tweetId) ->
    checkPermissions()
    check(tweetId, String)

    Datastream.update tweetId,
      $unset: { hidden: null }

  dataLink: (tweetId, eventId) ->
    checkPermissions()
    check(tweetId, String)
    check(eventId, String)

    # Attach this tweet to the event
    Events.update eventId,
      $addToSet: { sources: tweetId }

    # Attach this event to the tweet, unhide if necessary
    Datastream.update tweetId,
      $addToSet: { events: eventId }

    if @isSimulation
      Mapper.events.emit("data-link")
    else
      @unblock()
      TurkServer.log
        action: "data-link"
        dataId: tweetId
        eventId: eventId

    return

  dataUnlink: (tweetId, eventId) ->
    checkPermissions()
    check(tweetId, String)
    check(eventId, String)

    # TODO if multi-tagging is allowed, don't hide here
    Datastream.update tweetId,
      $pull: { events: eventId }
      $set: { hidden: true }

    Events.update eventId,
      $pull: { sources: tweetId }

    unless @isSimulation
      @unblock()
      TurkServer.log
        action: "data-unlink"
        dataId: tweetId
        eventId: eventId

    return

  # Dragging a tweet frome one event to another
  dataMove: (tweetId, fromEventId, toEventId) ->
    checkPermissions()
    check(tweetId, String)
    check(fromEventId, String)
    check(toEventId, String)

    Events.update fromEventId,
      $pull: { sources: tweetId }

    # In order for the tweet not to show up in the datastream during this
    # process, we need to add the new event before pulling the old one
    Datastream.update tweetId,
      $addToSet: { events: toEventId }

    Datastream.update tweetId,
      $pull: { events: fromEventId }

    Events.update toEventId,
      $addToSet: { sources: tweetId }

    unless @isSimulation
      @unblock()
      TurkServer.log
        action: "data-move"
        dataId: tweetId
        fromEventId: fromEventId
        toEventId: toEventId

    return

  ###
    Event Methods
  ###
  createEvent: (eventId, fields) ->
    checkPermissions()
    check(eventId, String)

    obj = {
      _id: eventId
      sources: []
    # location: undefined
    }

    _.extend(obj, fields)

    # On server, increment number based on highest numbered event (including deleted)
    # TODO: is this causing events to bounce around on client?
    unless @isSimulation
      maxEventIdx = Events.findOne({}, sort: {num: -1})?.num || 0
      obj.num = maxEventIdx + 1

    Events.insert(obj)

    if @isSimulation
      Mapper.events.emit("event-create")
    else
      @unblock()
      TurkServer.log
        action: "event-create"
        eventId: eventId
    return

  editEvent: (eventId) ->
    checkPermissions()
    check(eventId, String)

    userId = Meteor.userId()
    unless userId?
      bootbox.alert("Sorry, you must be logged in to make edits.") if @isSimulation
      return

    event = Events.findOne(eventId)

    # TODO An edit event across an instance ending will throw a (no-op) error here.
    unless event.editor
      Events.update eventId,
        $set: { editor: userId }
      if @isSimulation
        Mapper.events.emit("event-edit")
      else
        @unblock()
        TurkServer.log
          action: "event-edit"
          eventId: eventId

    else if @isSimulation and event.editor isnt userId
      bootbox.alert("Sorry, someone is already editing that event.")

    return

  updateEvent: (eventId, fields) ->
    checkPermissions()
    check(eventId, String)

    Events.update eventId,
      $set: fields

    if @isSimulation
      for key of fields
        break
      Mapper.events.emit("event-update-" + key)
    else
      @unblock()
      TurkServer.log
        action: "event-update"
        eventId: eventId
        fields: fields

    return

  unmapEvent: (eventId) ->
    checkPermissions()
    check(eventId, String)

    Events.update eventId,
      $unset: location: null

    unless @isSimulation
      @unblock()
      TurkServer.log
        action: "event-unmap"
        eventId: eventId

    return

  saveEvent: (eventId) ->
    check(eventId, String)

    Events.update eventId,
      $unset: { editor: 1 }

    if @isSimulation
      Mapper.events.emit("event-save")
    else
      @unblock()
      TurkServer.log
        action: "event-save"
        eventId: eventId

    return

  voteEvent: (eventId) ->
    checkPermissions()
    check(eventId, String)

    userId = Meteor.userId()
    unless userId
      bootbox.alert("You must be logged in to vote on an event.") if @isSimulation
      return

    Events.update eventId,
      $addToSet: { votes: userId }

    if @isSimulation
      Mapper.events.emit("event-vote")
    else
      @unblock()
      TurkServer.log
        action: "event-vote"
        eventId: eventId

    return

  unvoteEvent: (eventId) ->
    check(eventId, String)

    userId = Meteor.userId()

    unless userId
      bootbox.alert("You must be logged in to vote on an event.") if @isSimulation
      return

    Events.update eventId,
      $pull: { votes: userId }

    unless @isSimulation
      @unblock()
      TurkServer.log
        action: "event-unvote"
        eventId: eventId

    return

  deleteEvent: (eventId) ->
    checkPermissions()
    check(eventId, String)

    # Pull all tweet links
    # TODO: If multi-linking is ever re-enabled, reset tweet state here

#    event = Events.findOne(eventId)
#    _.each event.sources, (tweetId) ->
#      Datastream.update tweetId,
#        $pull: { events: eventId }

    # Don't actually delete event, so we retain the data and keep the number
    Events.update eventId,
      $set: {deleted: true}

    unless @isSimulation
      @unblock()
      TurkServer.log
        action: "event-delete"
        eventId: eventId

    return

  ###
    Doc Methods
  ###
  createDocument: (docName) ->
    checkPermissions()
    check(docName, String)

    docId = Documents.insert
      title: docName

    if @isSimulation
      Mapper.events.emit("document-create")
    else
      @unblock()
      TurkServer.log
        action: "document-create"
        docId: docId
        name: docName

    return docId

  renameDocument: (docId, newTitle) ->
    checkPermissions()
    check(docId, String)
    check(newTitle, String)

    Documents.update docId,
      $set: { title: newTitle }

    unless @isSimulation
      @unblock()
      TurkServer.log
        action: "document-rename"
        docId: docId
        name: newTitle

    return

  deleteDocument: (docId) ->
    checkPermissions()
    check(docId, String)

    Documents.update docId,
      $set: {deleted: true}

    unless @isSimulation
      @unblock()
      TurkServer.log
        action: "document-delete"
        docId: docId

    return

  ###
    Chat Methods
  ###
  createChat: (roomName) ->
    checkPermissions()
    check(roomName, String)

    roomId = ChatRooms.insert
      name: roomName
      users: 0

    if @isSimulation
      Mapper.events.emit("chat-create")
    else
      @unblock()
      TurkServer.log
        action: "chat-create"
        room: roomId
        name: roomName

    return roomId

  renameChat: (roomId, newName) ->
    checkPermissions()
    check(roomId, String)
    check(newName, String)

    ChatRooms.update roomId,
      $set: { name: newName }

    unless @isSimulation
      @unblock()
      TurkServer.log
        action: "chat-rename"
        room: roomId
        name: newName

    return

  ###

  inviteChat: server only

  sendChat: does extra stuff on server

  ###

  deleteChat: (roomId) ->
    checkPermissions()
    check(roomId, String)

    if @isSimulation
      # Client stub - do a quick check
      unless ChatRooms.findOne(roomId).users is 0
        bootbox.alert "You can only delete empty chat rooms."
      else
        ChatRooms.update roomId,
          $set: {deleted: true}
    else
      # Server method
      return unless ChatUsers.find(roomId: roomId).count() is 0
      ChatRooms.update roomId,
        $set: {deleted: true}

      # Both the rooms and the messages will be kept
      @unblock()
      TurkServer.log
        action: "chat-delete"
        room: roomId

    return

  ###
    Notifications
  ###

  # inviteChat: does stuff on server

  readNotification: (noteId) ->
    check(noteId, String)

    now = new Date()

    Notifications.update noteId,
      $set: {read: now}
    # This logs itself

    unless @isSimulation
      # Mark other notifications for the same user and same room read as well
      # but with a special flag
      note = Notifications.findOne(noteId)

      Notifications.update({
        user: note.user,
        room: note.room,
        read: {$exists: false}
      }, {
        $set: {
          read: now
          implicit: true
        }
      }, {multi: true})

    return

