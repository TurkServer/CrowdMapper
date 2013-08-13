# Chat
this.ChatRooms = new Meteor.Collection("chatrooms")
this.ChatUsers = new Meteor.Collection("chatusers")
this.ChatMessages = new Meteor.Collection("chatmessages")

# Datastream
this.Datastream = new Meteor.Collection("datastream")

# Docs
this.Documents = new Meteor.Collection("docs")

# Events / Map
this.Events = new Meteor.Collection("events")

Meteor.methods
  ###
    Event Methods
  ###
  createEvent: (eventId, fields) ->
    obj = {
      _id: eventId
      sources: []
      # location: undefined
    }

    _.extend(obj, fields)

    Events.insert(obj)

  editEvent: (id) ->
    userId = Meteor.userId()
    unless userId?
      bootbox.alert("Sorry, you must be logged in to make edits.") if @isSimulation
      return

    event = Events.findOne(id)

    unless event.editor
      Events.update id,
        $set: { editor: userId }
    else if @isSimulation and event.editor isnt userId
      bootbox.alert("Sorry, someone is already editing that event.")

  deleteEvent: (id) ->
    Events.remove(id)

  ###
    Chat Methods
  ###
  createChat: (roomName) ->
    ChatRooms.insert
      name: roomName
      users: 0

  sendChat: (roomId, message) ->
    userId = Meteor.userId()
    return unless Meteor.userId()

    obj = {
      room: roomId
      userId: userId
      text: message
    }

    # Attach server-side timestamps to chat messages
    obj.timestamp = +(new Date()) unless @isSimulation

    ChatMessages.insert(obj)


  deleteChat: (roomId) ->
    if @isSimulation
      # Client stub - do a quick check
      count = ChatRooms.findOne(roomId).users
      unless count is 0
        bootbox.alert "You can only delete empty chat rooms."
      else
        ChatRooms.remove roomId
    else
      # Server method
      return unless ChatUsers.find(roomId: roomId).count() is 0
      ChatRooms.remove roomId
      # TODO should we delete messages? Or use them for logging...
