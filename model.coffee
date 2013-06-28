# Chat
this.ChatRooms = new Meteor.Collection("chatrooms")
this.ChatUsers = new Meteor.Collection("chatusers")
this.ChatMessages = new Meteor.Collection("chatmessages")

# Docs
this.Documents = new Meteor.Collection("docs")

# Events / Map
this.Events = new Meteor.Collection("events")

Meteor.methods
  getUsername: (id) -> Meteor.users.find(_id: id).username
