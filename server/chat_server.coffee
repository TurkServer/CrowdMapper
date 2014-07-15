# Don't persist the contents of this collection
@ChatUsers = new Meteor.Collection("chatusers") #, {connection: null})

# Because it is in the DB, we can have this index
ChatUsers._ensureIndex({roomId: 1})

# Index chat messages by room and then by timestamp.
# It will not be partitioned by TurkServer.
ChatMessages._ensureIndex({ room: 1, timestamp: 1})

# Managed by TurkServer; publish all chatrooms
# Deleted chatrooms are filtered on the client
Meteor.publish "chatrooms", -> ChatRooms.find()

# Generalize what we are doing below

enterRoom = (sessionId, roomId, userId) ->
  ChatUsers.upsert sessionId,
    $set: { userId, roomId }

  ChatRooms.update roomId,
    $inc: { users: 1 }

  TurkServer.log
    action: "room-enter"
    room: roomId

leaveRoom = (sessionId, roomId, userId) ->
  # Remove the chatuser record unless they changed rooms
  ChatUsers.remove
    _id: sessionId
    roomId: roomId

  ChatRooms.update roomId,
    $inc: { users: -1 }

# Because this is no longer a null connection, clear it on startup
Meteor.startup ->
  ChatUsers.remove({})

# Clear all users stored in chatrooms on start
TurkServer.startup ->
  ChatRooms.update {},
    $set:
      {users: 0}
  , multi: true

# Clean up any chat state when a user disconnects
UserStatus.events.on "connectionLogout", (doc) ->
  # No groupId used here because ChatUsers and ChatRooms are not partitioned
  if (existing = ChatUsers.findOne(doc.sessionId))?
    leaveRoom(doc.sessionId, existing.roomId, doc.userId)

# publish messages and users for a room
Meteor.publish "chatstate", (room)  ->
  userId = @userId
  return [] unless userId? # No chat for unauthenticated users
  sessionId = @_session.id

  # Don't update room state for admin
  unless Meteor.users.findOne(userId)?.admin
    # don't try to enter room if no room specified
    return [] unless room

    # Update room state - except for admin
    enterRoom(sessionId, room, userId)

    this.onStop ->
      # Leave this room when the subscription is stopped
      leaveRoom(sessionId, room, userId)
  else
    # Don't publish arbitrary rooms to admin
    return [] unless room

  return [
    ChatUsers.find(roomId: room),
    ChatMessages.find(room: room)
  ]

userRegex = new RegExp('(^|\\b|\\s)(@[\\w.]+)($|\\b|\\s)','g')

unreadNotificationExists = (user, sender, room, type) ->
  return Notifications.findOne({user, sender, room, type, read: {$exists: false} })?

Meteor.methods
  inviteChat: (userId, roomId) ->
    TurkServer.checkNotAdmin()
    check(userId, String)
    check(roomId, String)

    myId = Meteor.userId()
    return unless myId?
    # Don't invite if user is already in the same room
    return if ChatUsers.findOne(userId: userId)?.roomId is roomId

    # Skip invite if this user already has an outstanding invitee to the other user to this room
    return if unreadNotificationExists(userId, myId, roomId, "invite")

    Notifications.insert
      user: userId
      sender: myId
      type: "invite"
      room: roomId
      timestamp: new Date()

    # No need to log this, we have it as a notification
    return

  sendChat: (roomId, message) ->
    TurkServer.checkNotAdmin()
    check(roomId, String)
    check(message, String)

    userId = Meteor.userId()
    return unless userId?

    chatTime = new Date()

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

      return if unreadNotificationExists(targetUser._id, userId, roomId, "mention")

      Notifications.insert
        user: targetUser._id
        sender: userId
        type: "mention"
        room: roomId
        timestamp: chatTime
