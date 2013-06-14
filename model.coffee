
this.ChatRooms = new Meteor.Collection("chatrooms")
this.ChatMessages = new Meteor.Collection("chatmessages")

this.Events = new Meteor.Collection("events")

Meteor.methods
  getUsername: (id) -> Meteor.users.find(_id: id).username
