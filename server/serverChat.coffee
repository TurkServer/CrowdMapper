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
  # TODO handle things properly when a user logs out and do not let logged out users subscribe...
  userId = @_session.userId
  sessionId = @_session.id

  # Leave any existing room
  existing = ChatUsers.findOne(sessionId)
  leaveRoom(existing.roomId, existing.userId) if existing

  # don't try to enter room if not in room or not logged in
  if not room or not userId
    ChatUsers.remove(sessionId) if existing
    return

  # Enter new room
  if existing
    ChatUsers.update sessionId,
      $set:
        userId: userId
        roomId: room
  else
    ChatUsers.insert
      _id: sessionId,
      userId: userId
      roomId: room

  enterRoom(room, userId)

  # publish room messages and users
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
  # TODO use findAndUpdate here once supported
  existing = ChatUsers.findOne(sessionId)
  leaveRoom(existing.roomId, userId) if existing

  ChatUsers.remove(sessionId) if existing
