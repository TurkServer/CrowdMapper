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
