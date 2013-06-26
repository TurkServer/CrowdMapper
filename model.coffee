
this.ChatRooms = new Meteor.Collection("chatrooms")
this.ChatMessages = new Meteor.Collection("chatmessages")

this.Documents = new Meteor.Collection("docs")

this.Events = new Meteor.Collection("events")

Meteor.methods
  getUsername: (id) -> Meteor.users.find(_id: id).username
