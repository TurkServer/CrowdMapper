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

    if @isSimulation
      Mapper.events.emit("data-hide")
    else
      @unblock()
      TurkServer.log
        action: "data-hide"
        dataId: id

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
    TurkServer.checkNotAdmin()
    return unless tweetId and eventId

    Datastream.update tweetId,
      $pull: { events: eventId }

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
    TurkServer.checkNotAdmin()
    check(tweetId, String)
    check(fromEventId, String)
    check(toEventId, String)

    Events.update fromEventId,
      $pull: { sources: tweetId }

    Datastream.update tweetId,
      $pull: { events: fromEventId }
      $addToSet: { events: toEventId }

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
    TurkServer.checkNotAdmin()

    obj = {
      _id: eventId
      sources: []
    # location: undefined
    }

    _.extend(obj, fields)

    # On server, increment number based on highest numbered event (including deleted)
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
      if @isSimulation
        Mapper.events.emit("event-edit")
      else
        @unblock()
        TurkServer.log
          action: "event-edit"
          eventId: id

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
    else
      @unblock()
      TurkServer.log
        action: "event-update"
        eventId: id
        fields: fields

    return

  unmapEvent: (id) ->
    TurkServer.checkNotAdmin()

    Events.update id,
      $unset: location: null

    unless @isSimulation
      @unblock()
      TurkServer.log
        action: "event-unmap"
        eventId: id

    return

  saveEvent: (id) ->
    Events.update id,
      $unset: { editor: 1 }

    if @isSimulation
      Mapper.events.emit("event-save")
    else
      @unblock()
      TurkServer.log
        action: "event-save"
        eventId: id

    return

  voteEvent: (id) ->
    TurkServer.checkNotAdmin()
    userId = Meteor.userId()
    unless userId
      bootbox.alert("You must be logged in to vote on an event.") if @isSimulation
      return

    Events.update id,
      $addToSet: { votes: userId }

    if @isSimulation
      Mapper.events.emit("event-vote")
    else
      @unblock()
      TurkServer.log
        action: "event-vote"
        eventId: id

    return

  unvoteEvent: (id) ->
    userId = Meteor.userId()
    unless userId
      bootbox.alert("You must be logged in to vote on an event.") if @isSimulation
      return

    Events.update id,
      $pull: { votes: userId }

    unless @isSimulation
      @unblock()
      TurkServer.log
        action: "event-unvote"
        eventId: id

    return

  deleteEvent: (id) ->
    TurkServer.checkNotAdmin()
    event = Events.findOne(id)

    # Pull all tweet links
    _.each event.sources, (tweetId) ->
      Datastream.update tweetId,
        $pull: { events: id }

    # Don't actually delete event, so we retain the data and keep the number
    Events.update id,
      $set: {deleted: true}

    unless @isSimulation
      @unblock()
      TurkServer.log
        action: "event-delete"
        eventId: id

    return

  ###
    Doc Methods
  ###
  createDocument: (docName) ->
    TurkServer.checkNotAdmin()

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
    TurkServer.checkNotAdmin()
    Documents.update docId,
      $set: { title: newTitle }

    unless @isSimulation
      @unblock()
      TurkServer.log
        action: "document-rename"
        docId: docId
        name: newTitle

    return

  deleteDocument: (id) ->
    TurkServer.checkNotAdmin()
    Documents.update id,
      $set: {deleted: true}

    unless @isSimulation
      @unblock()
      TurkServer.log
        action: "document-delete"
        docId: id

    return

  ###
    Chat Methods
  ###
  createChat: (roomName) ->
    TurkServer.checkNotAdmin()
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
    TurkServer.checkNotAdmin()
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
    TurkServer.checkNotAdmin()
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

