Template.rooms.events =
  "click #addRoom": ->
    roomName = window.prompt("Name the room", "My room") or "Anonymous Room"
    ChatRooms.insert name: roomName  if roomName

Template.chat.currentRoom = ->
  Session.get("room") or false

Template.rooms.availableRooms = ->
  ChatRooms.find {}

Template.roomItem.active = ->
  Session.get("room") is @_id

Template.roomItem.events =
  "click .enter": (e) ->
    e.preventDefault()

    name = undefined
    if Session.get("name") is `undefined`
      name = window.prompt("Your name", "Guest") or "Jerky"
      Session.set "name", name
    Session.set "room", @_id

  "click .delete": ->
    ChatRooms.remove _id: @_id

Template.room.roomName = ->
  room = ChatRooms.findOne(_id: Session.get("room"))
  room and room.name

Template.room.messages = ->
  ChatMessages.find room: Session.get("room")

# Not sure what this does but it breaks stuff
#  Template.messageItem.authorClass = ->
#    (if Session.equals("name", @author) then " mine" else "")

Template.room.events =
  "click #leave": ->
    return unless window.confirm("Leave this room?", "Do you really want to leave?")
    Session.set "room", `undefined`

  submit: ->
    $msg = $("#msg")
    if $msg.val()
      ChatMessages.insert
        room: Session.get("room")
        author: Session.get("name")
        text: $msg.val()
        timestamp: (new Date()).toUTCString()

    $msg.val ""
    $msg.focus()
    Meteor.flush()
    $("#messages").scrollTop 99999
