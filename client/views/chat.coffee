# Send room changes to server
# TODO this incurs a high traffic cost when switching between rooms
Deps.autorun ->
  roomId = Session.get("room")
  Meteor.subscribe "chatstate", roomId

Handlebars.registerHelper "currentRoom", -> Meteor.userId()? && Session.get("room")?

Template.chat.events =
  "click .action-room-create": (e) ->
    e.preventDefault()

    bootbox.prompt "Name the room", (roomName) ->
      Meteor.call "createChat", roomName if !!roomName

Template.rooms.availableRooms = -> ChatRooms.find {}

Template.roomItem.active = -> Session.equals("room", @_id)

Template.roomItem.empty = -> @users is 0

Template.roomItem.events =
  "click .action-room-enter": (e) ->
    e.preventDefault()

    unless Meteor.userId()
      bootbox.alert "You must be logged in to join chat rooms."
      return

    Session.set "room", @_id

  "click .action-room-delete": (e) ->
    e.preventDefault()
    Meteor.call("deleteChat", @_id)

    # don't select chatroom - http://stackoverflow.com/questions/10407783/stop-event-propagation-in-meteor
    e.stopImmediatePropagation()

Template.roomUsers.users = ->
  ChatUsers.find {}

Template.roomUsers.findUser = ->
  Meteor.users.findOne @userId

Template.currentChatroom.events =
  submit: (e, tmpl) ->
    e.preventDefault()
    $msg = $ tmpl.find(".chat-input")
    return unless $msg.val()

    Meteor.call "sendChat", Session.get("room"), $msg.val()

    $msg.val("")
    $msg.focus()
    Meteor.flush()

    # Auto scroll happens on messageBox render now..

Template.currentChatroom.settings = -> {
  position: "top"
  limit: 5
  rules: [
    {
      token: '@'
      collection: Meteor.users
      field: "username"
      template: Template.userPill
    },
    {
      token: '!'
      collection: Datastream
      field: "num"
      template: Template.tweetNumbered
    },
    {
      token: '#'
      collection: Events
      field: "num"
      template: Template.eventShort
    }
  ]
}

Template.roomHeader.rendered = ->
  settings =
    success: (response, newValue) ->
      roomId = Session.get("room")
      return unless roomId
      ChatRooms.update roomId,
        $set: { name: newValue }

  $(@find('.editable:not(.editable-click)')).editable('destroy').editable(settings)

Template.roomHeader.roomName = ->
  room = ChatRooms.findOne(_id: Session.get("room"))
  room and room.name

Template.roomHeader.events =
  "click .action-room-leave": ->
    # TODO convert this to a method call ... !
#    bootbox.confirm "Leave this room?", (value) ->
    Session.set("room", `undefined`) # if value

Template.messageBox.rendered = ->
  # Scroll down whenever anything happens
  $messages = $ @find(".messages")
  $messages.scrollTop $messages[0].scrollHeight

Template.messageBox.messages = ->
  ChatMessages.find
    room: Session.get("room")

# These usernames are nonreactive because find does not use any reactive variables
Template.messageItem.username = -> Meteor.users.findOne(@userId).username

userRegex = new RegExp('(^|\\b|\\s)(@[\\w.]+)($|\\b|\\s)','g')
tweetRegex = new RegExp('(^|\\b|\\s)(![\\d]+)($|\\b|\\s)','g')
eventRegex = new RegExp('(^|\\b|\\s)(#[\\d]+)($|\\b|\\s)','g')

# TODO remove ugly space added below
userFunc = (_, p1, p2) ->
  username = p2.substring(1)
  user = Meteor.users.findOne(username: username)
  return " " + if user then Template.userPill(user) else username

tweetFunc = (_, p1, p2) ->
  tweetNum = p2.substring(1)
  tweet = Datastream.findOne( {num: tweetNum} )
  return " " + if tweet then Template.tweetIconClickable(tweet) else tweetNum

eventFunc = (_, p1, p2) ->
  eventNum = parseInt( p2.substring(1) )
  event = Events.findOne( {num: eventNum} )
  return " " + if event then Template.eventIconClickable(event) else eventNum

# Replace any matched users, tweets, or events with links
Template.messageItem.renderText = ->
  text = Handlebars._escape(@text)
  # No SafeString needed here as long as renderText is unescaped
  text = text.replace userRegex, userFunc
  text = text.replace tweetRegex, tweetFunc
  text = text.replace eventRegex, eventFunc

Template.messageItem.eventText = ->
  username = Meteor.users.findOne(@userId).username
  return username + " has " + (if @event is "enter" then "entered" else "left" ) + " the room."
