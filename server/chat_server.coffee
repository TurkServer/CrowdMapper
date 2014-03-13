# Don't persist the contents of this collection
@ChatUsers = new Meteor.Collection("chatusers") #, {connection: null})

# Because it is in the DB, we can have this index
ChatUsers._ensureIndex({roomId: 1})

# Because this is no longer a null connection, clear it on startup
Meteor.startup ->
  ChatUsers.remove({})

# Index chat messages by room and then by timestamp.
# It will not be partitioned by TurkServer.
ChatMessages._ensureIndex({ room: 1, timestamp: 1})

# Managed by TurkServer; publish non-deleted chatrooms
Meteor.publish "chatrooms", ->
  ChatRooms.find(deleted: {$exists: false})

# Generalize what we are doing below

enterRoom = (roomId, userId) ->
  ChatRooms.update roomId,
    $inc: { users: 1 }
#  ChatMessages.insert
#    room: roomId
#    event: "enter"
#    userId: userId
#    timestamp: Date.now()
  TurkServer.log
    action: "room-enter"
    room: roomId

leaveRoom = (roomId, userId) ->
  ChatRooms.update roomId,
    $inc: { users: -1 }
#  ChatMessages.insert
#    room: roomId
#    event: "leave"
#    userId: userId
#    timestamp: Date.now()

# publish messages and users for a room
Meteor.publish "chatstate", (room)  ->
  userId = @userId
  return null unless userId # No chat for unauthenticated users
  sessionId = @_session.id

  # Don't update room state for admin
  unless Meteor.users.findOne(userId)?.admin
    # Leave any existing room
    existing = ChatUsers.findOne(sessionId)
    leaveRoom(existing.roomId, existing.userId) if existing

    # don't try to enter room if not in room or not logged in
    if not room or not userId
      ChatUsers.remove(sessionId) if existing
      return

    # Update room state - except for admin
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
  else
    # Don't publish arbitrary rooms to admin
    return unless room

  return [
    ChatUsers.find(roomId: room),
    ChatMessages.find(room: room)
  ]

# Clear all users stored in chatrooms on start
TurkServer.startup ->
  ChatRooms.update {},
    $set:
      {users: 0}
  , multi: true

userRegex = new RegExp('(^|\\b|\\s)(@[\\w.]+)($|\\b|\\s)','g')

Meteor.methods
  inviteChat: (userId, roomId) ->
    TurkServer.checkNotAdmin()
    myId = Meteor.userId()
    return unless myId
    # Don't invite if user is already in the same room
    return if ChatUsers.findOne(userId: userId)?.roomId is roomId

    # TODO Skip invite if this user has already invited the other user to this room
    Notifications.insert
      user: userId
      sender: myId
      type: "invite"
      room: roomId
      timestamp: Date.now()

    # No need to log this, we have it

  sendChat: (roomId, message) ->
    TurkServer.checkNotAdmin()
    userId = Meteor.userId()
    return unless Meteor.userId()

    chatTime = Date.now()

    obj =
      room: roomId
      userId: userId
      text: message
      timestamp: chatTime # Attach server-side timestamps to chat messages

    ChatMessages.insert(obj)
    @unblock()

    # Parse and generate any notifications from this chat, using this regex ability
    message.replace userRegex, (_, p1, p2) ->
      targetUser = Meteor.users.findOne({username: p2.substring(1)})
      return unless targetUser?
      # Don't notify if user is already in the same room
      return if ChatUsers.findOne(userId: targetUser._id)?.roomId is roomId
      Notifications.insert
        user: targetUser._id
        sender: userId
        type: "mention"
        room: roomId
        timestamp: chatTime

# Clean up any chat state when a user disconnects
UserStatus.events.on "sessionLogout", (doc) ->
  # No groupId needed here because ChatUsers and ChatRooms are not partitioned
  # TODO use findAndUpdate here once supported
  existing = ChatUsers.findOne(doc.sessionId)
  leaveRoom(existing.roomId, doc.userId) if existing

  ChatUsers.remove(doc.sessionId) if existing
