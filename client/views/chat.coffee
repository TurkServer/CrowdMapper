# Send room changes to server
# TODO this incurs a high traffic/rendering cost when switching between rooms
Deps.autorun ->
  roomId = Session.get("room")
  Session.set("chatRoomReady", false)
  Meteor.subscribe("chatstate", roomId, -> Session.set("chatRoomReady", true))

# This should only change if the room changes, else chat box will be re-rendering a lot
Handlebars.registerHelper "currentRoom", ->
  return unless Meteor.userId()?
  # Return room only if it exists in the collection (not deleted)
  return ChatRooms.findOne(Session.get("room"), {fields: _id: 1})?._id

Template.chat.events
  "click .action-room-create": (e) ->
    e.preventDefault()

    bootbox.prompt "Name the room", (roomName) ->
      return unless !!roomName
      Meteor.call "createChat", roomName, (err, id) ->
        return unless id
        Session.set "room", id

Template.currentChatroom.events
  "click .action-room-leave": ->
    # TODO convert this to a method call ... !
    #    bootbox.confirm "Leave this room?", (value) ->
    Session.set("room", undefined) # if value

Template.currentChatroom.nameDoc = -> ChatRooms.findOne(""+@, {fields: name: 1})

Template.rooms.loaded = -> Session.equals("chatSubReady", true)

Template.rooms.availableRooms = ->
  selector = if TurkServer.isAdmin() and Session.equals("adminShowDeleted", true) then {}
  else { deleted: {$exists: false} }
  ChatRooms.find(selector, {sort: {name: 1}}) # For a consistent ordering

Template.roomItem.active = -> if Session.equals("room", @_id) then "active" else ""
Template.roomItem.deleted = -> if @deleted then "deleted" else ""

Template.roomItem.empty = -> @users is 0

Template.roomItem.events =
  "click .action-room-enter": (e) ->
    e.preventDefault()

    unless Meteor.userId()
      bootbox.alert "You must be logged in to join chat rooms."
      return

    Session.set "room", @_id
    Mapper.events.emit("chat-join")

  "click .action-room-delete": (e) ->
    e.preventDefault()
    roomId = @_id
    bootbox.confirm "This will delete the chat room and its messages. Are you sure?", (res) ->
      return unless res # Only if "yes" clicked
      Meteor.call("deleteChat", roomId) if roomId

    # don't select chatroom (above function) - http://stackoverflow.com/questions/10407783/stop-event-propagation-in-meteor
    e.stopImmediatePropagation()

Template.roomUsers.users = ->
  ChatUsers.find {}

Template.roomUsers.findUser = ->
  Meteor.users.findOne @userId

Template.roomHeader.rendered = ->
  tmplInst = this

  this.autorun ->
    # Trigger this whenever title changes - note only name is reactively depended on
    Blaze.getCurrentData()
    # Destroy old editable if it exists
    tmplInst.$(".editable").editable("destroy").editable
      display: ->
      success: (response, newValue) ->
        roomId = Session.get("room")
        return unless roomId
        Meteor.call "renameChat", roomId, newValue

showEvent = (eventId) ->
  Mapper.switchTab 'events' # Make sure we are on the event page
  # Set up a scroll event, then trigger a re-render
  Mapper.selectEvent(eventId)
  Mapper.scrollToEvent(eventId)

Template.messageBox.events =
  "click .tweet-icon.clickme": (e) ->
    tweetId = $(e.target).data("tweetid") + "" # Ensure string, not integer
    data = Datastream.findOne(tweetId)
    return unless data

    # Error message if tweet is hidden, or went on a deleted event
    if data.hidden or Events.findOne(data.events?[0])?.deleted
      bootbox.alert("That data has been deleted.")
      return

    if data.events? and data.events.length > 0
      showEvent data.events[0] # Scroll to event
    else
      Mapper.selectData(tweetId)
      Mapper.scrollToData(tweetId)

  "click .event-icon.clickme": (e) ->
    eventId = $(e.target).data("eventid") + ""
    event = Events.findOne(eventId)
    return unless event

    if event.deleted
      bootbox.alert("That event has been deleted.")
      return

    showEvent(eventId)

Template.messageBox.loaded = -> Session.equals("chatRoomReady", true)

Template.messageBox.messages = ->
  ChatMessages.find {},
    # room: Session.get("room")
    sort: {timestamp: 1}

# These usernames are nonreactive because find does not use any reactive variables
Template.messageItem.username = ->
  Meteor.users.findOne(@userId)?.username || @userId

# If updating the user, also update server notification generations.
userRegex = new RegExp('(^|\\b|\\s)(@[\\w.]+)($|\\b|\\s)','g')
tweetRegex = new RegExp('(^|\\b|\\s)(~[\\d]+)($|\\b|\\s)','g')
eventRegex = new RegExp('(^|\\b|\\s)(#[\\d]+)($|\\b|\\s)','g')

renderWithData = (kind, data) ->
  Blaze.toHTML Blaze.With data, -> kind

# TODO: remove ugly spaces added below
# TODO: user status won't update reactively here; it just stays its initial value
userFunc = (_, p1, p2) ->
  username = p2.substring(1)
  user = Meteor.users.findOne(username: username)
  return " " + if user then renderWithData(Template.userPill, user) else p2

tweetFunc = (_, p1, p2) ->
  tweetNum = parseInt( p2.substring(1) )
  tweet = Datastream.findOne( {num: tweetNum} )
  return " " + if tweet then renderWithData(Template.tweetIconClickable, tweet) else p2

eventFunc = (_, p1, p2) ->
  eventNum = parseInt( p2.substring(1) )
  event = Events.findOne( {num: eventNum} )
  return " " + if event then renderWithData(Template.eventIconClickable, event) else p2

# Because messages only render when inserted, we can use this to scroll the chat window
Template.messageItem.rendered = ->
  # Scroll down whenever anything happens
  $messages = $(".messages-body")
  $messages.scrollTop $messages[0].scrollHeight

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

Template.chatInput.rendered = ->
  $(@find(".chat-help")).popover
    html: true
    placement: "top"
    trigger: "hover"
    content: Blaze.toHTML Template.chatPopover

Template.chatInput.events =
  submit: (e, tmpl) ->
    e.preventDefault()
    $msg = $( tmpl.find(".chat-input") )
    return unless $msg.val()

    Meteor.call "sendChat", Session.get("room"), $msg.val() # Server only method

    $msg.val("")
    $msg.focus()
    Meteor.flush()

    # Auto scroll happens on messageBox render now..
    Mapper.events.emit("chat-message")

# RegExp syntax below taken from
# https://github.com/meteor/meteor/blob/devel/packages/minimongo/selector.js
# We use $where because we need the regex to match on a number!
# This worked before but was removed in 0.7.1:
# https://github.com/meteor/meteor/pull/1874#issuecomment-37074734
# However, since it's all on the client, this will result in the same performance.
numericMatcher = (filter) ->
  re = new RegExp("^" + filter)
  return { $where: -> re.test(@num) }

Template.chatInput.settings = -> {
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
      token: '~'
      collection: Datastream
      field: "num"
      template: Template.tweetNumbered
      # TODO this can select tweets attached to deleted events, but error
      # shows up when they are clicked
      filter: { hidden: $exists: false }
      selector: numericMatcher
    },
    {
      token: '#'
      collection: Events
      field: "num"
      template: Template.eventShort
      filter: { deleted: $exists: false }
      selector: numericMatcher
    }
  ]
}
