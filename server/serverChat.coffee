Meteor.publish "chatrooms", ->
  ChatRooms.find()

enterRoom = (roomId, userId) ->
  ChatRooms.update roomId,
    $inc: { users: 1 }
  ChatMessages.insert
    room: roomId
    text: Meteor.users.findOne(userId).username + " entered the room."

leaveRoom = (roomId, userId) ->
  ChatRooms.update roomId,
    $inc: { users: -1 }
  ChatMessages.insert
    room: roomId
    text: Meteor.users.findOne(userId).username + " left the room."

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
    leaveRoom(existing.roomId, userId)
    ChatUsers.update sessionId,
      $set:
        userId: userId
        roomId: room

  enterRoom(room, userId)

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

  leaveRoom(existing.roomId, userId)

  ChatUsers.remove(sessionId)
