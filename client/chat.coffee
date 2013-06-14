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

    unless Meteor.user().username
      alert "You must choose a name to join chat rooms."
      return

    Session.set "room", @_id

  "click .delete": (e) ->
    e.preventDefault()

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
        author: Meteor.user().username
        text: $msg.val()
        timestamp: (new Date()).toUTCString()

    $msg.val ""
    $msg.focus()
    Meteor.flush()

    # Silly way of auto scrolling down. Fix.
    $(".messages").scrollTop 99999
