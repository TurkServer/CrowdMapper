
# User status and profile
Meteor.publish "userStatus", ->
  Meteor.users.find { "profile.online": true },
    fields:
      'username': 1
      'profile': 1

# TODO: Improve the publication logic

Meteor.publish "chatrooms", ->
  ChatRooms.find()

Meteor.publish "chatmessages", ->
  ChatMessages.find()

Meteor.publish "events", ->
  Events.find()
