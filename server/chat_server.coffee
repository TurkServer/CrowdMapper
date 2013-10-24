# Don't persist the contents of this collection
@ChatUsers = new Meteor.Collection("chatusers", {connection: null})

Meteor.publish "chatrooms", ->
  ChatRooms.find()

enterRoom = (roomId, userId) ->
  ChatRooms.update roomId,
    $inc: { users: 1 }
#  ChatMessages.insert
#    room: roomId
#    event: "enter"
#    userId: userId
#    timestamp: +(new Date())

leaveRoom = (roomId, userId) ->
  ChatRooms.update roomId,
    $inc: { users: -1 }
#  ChatMessages.insert
#    room: roomId
#    event: "leave"
#    userId: userId
#    timestamp: +(new Date())

# publish messages and users for a room
Meteor.publish "chatstate", (room)  ->
  # TODO handle things properly when a user logs out and do not let logged out users subscribe...
  userId = @userId # @_session.userId
  return null unless userId
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

# Clear all users stored in chatrooms on start
Meteor.startup ->
  ChatRooms.update {},
    $set:
      {users: 0}
  , multi: true

userRegex = new RegExp('(^|\\b|\\s)(@[\\w.]+)($|\\b|\\s)','g')

Meteor.methods
  sendChat: (roomId, message) ->
    userId = Meteor.userId()
    return unless Meteor.userId()

    obj =
      room: roomId
      userId: userId
      text: message
      timestamp: +(new Date()) # Attach server-side timestamps to chat messages

    ChatMessages.insert(obj)
    @unblock()

    # Parse and generate any notifications from this chat
    # TODO need we escape this?
    # text = Handlebars._escape(message)
    message.replace userRegex, (_, p1, p2) ->
      targetUser = Meteor.users.findOne({username: p2.substring(1)})
      return unless targetUser?
      Notifications.insert
        user: targetUser._id
        sender: userId
        type: "mention"
        room: roomId

# Clean up any chat rooms on logout
UserStatus.on "sessionLogout", (userId, sessionId) ->
  # TODO use findAndUpdate here once supported
  existing = ChatUsers.findOne(sessionId)
  leaveRoom(existing.roomId, userId) if existing

  ChatUsers.remove(sessionId) if existing
