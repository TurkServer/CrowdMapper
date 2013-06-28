
# User status and profile
Meteor.publish "userStatus", ->
  Meteor.users.find { "profile.online": true },
    fields:
      'username': 1
      'profile': 1

# TODO: Improve the publication logic

Meteor.publish "chatrooms", ->
  ChatRooms.find()

# publish messages and users for a room
Meteor.publish "chatstate", (room)  ->
  userId = @_session.userId
  sessionId = @_session.id

  existing = ChatUsers.findOne(sessionId)

  unless existing
    ChatUsers.insert
      _id: sessionId,
      userId: userId
      roomId: room
  else
    ChatRooms.update existing.roomId,
      $inc: { users: -1 }
    ChatUsers.update sessionId,
      $set:
        userId: userId
        roomId: room

  ChatRooms.update room,
    $inc: { users: 1 }

  Meteor.publishWithRelations
    handle: this,
    collection: ChatRooms,
    filter: room,
    mappings: [{
      reverse: true
      key: 'roomId',
      collection: ChatUsers
    }, {
      reverse: true,
      key: 'room',
      collection: ChatMessages
    }]

# Clean up any chat rooms on logout
UserStatus.on "sessionLogout", (userId, sessionId) ->
  # TODO replace with findAndUpdate
  existing = ChatUsers.findOne(sessionId)
  ChatRooms.update existing.roomId,
    $inc: { users: -1 }

  ChatUsers.remove(sessionId)

Meteor.publish "docs", ->
  Documents.find()

Meteor.publish "events", ->
  Events.find()
