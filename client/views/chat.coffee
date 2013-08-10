# Send room changes to server
# TODO this incurs a high traffic cost when switching between rooms
Deps.autorun ->
  roomId = Session.get("room")
  Meteor.subscribe "chatstate", roomId

Template.chat.events =
  "click #addRoom": (e) ->
    e.preventDefault()

    bootbox.prompt "Name the room", (roomName) ->
      ChatRooms.insert({
        name: roomName
        users: 0
      }) if !!roomName

Template.chat.currentRoom = -> Session.get("room") or false

Template.rooms.availableRooms = -> ChatRooms.find {}

Template.roomItem.active = -> Session.equals("room", @_id)

Template.roomItem.empty = -> @users is 0

Template.roomItem.events =
  "click .action-room-enter": (e) ->
    e.preventDefault()

    unless Meteor.user().username
      bootbox.alert "You must choose a name to join chat rooms."
      return

    Session.set "room", @_id

  "click .delete": (e) ->
    e.preventDefault()
    Meteor.call("deleteChat", @_id)

    # don't select chatroom - http://stackoverflow.com/questions/10407783/stop-event-propagation-in-meteor
    e.stopImmediatePropagation()

Template.roomUsers.users = ->
  ChatUsers.find {}

Template.roomUsers.findUser = ->
  Meteor.users.findOne @userId

Template.room.messages = ->
  ChatMessages.find room: Session.get("room")

# Not sure what this does but it breaks stuff
#  Template.messageItem.authorClass = ->
#    (if Session.equals("name", @author) then " mine" else "")

Template.room.events =
  "click #leave": ->
    bootbox.confirm "Leave this room?", (value) ->
      Session.set("room", `undefined`) if value

  submit: ->
    $msg = $("#msg")
    return unless $msg.val()

    ChatMessages.insert
      room: Session.get("room")
      author: Meteor.user().username
      text: $msg.val()
      timestamp: +(new Date())

    $msg.val ""
    $msg.focus()
    Meteor.flush()

    # Silly way of auto scrolling down. Also do on others' messages.
    $messages = $(".messages")
    $messages.scrollTop $messages[0].scrollHeight

Template.roomTitle.rendered = ->
  settings =
    success: (response, newValue) ->
      roomId = Session.get("room")
      return unless roomId
      ChatRooms.update roomId,
        $set: { name: newValue }

  $(@find('.editable:not(.editable-click)')).editable('destroy').editable(settings)

Template.roomTitle.roomName = ->
  room = ChatRooms.findOne(_id: Session.get("room"))
  room and room.name
