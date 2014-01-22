# Don't persist the contents of this collection
@ChatUsers = new Meteor.Collection("chatusers", {connection: null})

# Index chat messages by room and then by timestamp.
# It will not be partitioned by TurkServer.
ChatMessages._ensureIndex({ room: 1, timestamp: 1})

Meteor.publish "chatrooms", ->
  ChatRooms.find()

# TODO store or log the enter/leave messages below

enterRoom = (roomId, userId) ->
  ChatRooms.update roomId,
    $inc: { users: 1 }
#  ChatMessages.insert
#    room: roomId
#    event: "enter"
#    userId: userId
#    timestamp: Date.now()

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
  inviteChat: (userId, roomId) ->
    myId = Meteor.userId()
    return unless myId

    Notifications.insert
      user: userId
      sender: myId
      type: "invite"
      room: roomId
      timestamp: Date.now()

  sendChat: (roomId, message) ->
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
        timestamp: chatTime

# Clean up any chat rooms on logout
UserStatus.on "sessionLogout", (doc) ->
  # TODO bind groupId here or make TurkServer functionality
  # TODO use findAndUpdate here once supported
  existing = ChatUsers.findOne(doc.sessionId)
  leaveRoom(existing.roomId, doc.userId) if existing

  ChatUsers.remove(doc.sessionId) if existing
