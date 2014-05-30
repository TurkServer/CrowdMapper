Template.notifications.notifications = ->
  return Notifications.find {},
    # show most recent first
    sort: {timestamp: -1}

Template.notifications.glowClass = ->
  if Notifications.find().count() > 0 then "glowing" else ""

Template.notifications.notificationCount = ->
  return Notifications.find().count()

Template.notifications.notificationTemplate = ->
  switch @type
    when "invite" then Template._inviteNotification
    when "mention" then Template._mentionNotification
    else null

notifyEvents =
  'click a': (e) ->
    e.preventDefault()
    Session.set("room", this.room)
    Meteor.call "readNotification", this._id
      
Template._inviteNotification.events = notifyEvents
Template._mentionNotification.events = notifyEvents
  
notifyUsername = ->
  Meteor.users.findOne(@sender)?.username
  
notifyRoomname = ->
  ChatRooms.findOne(@room)?.name
  
Template._inviteNotification.username = notifyUsername
Template._mentionNotification.username = notifyUsername

Template._inviteNotification.roomname = notifyRoomname
Template._mentionNotification.roomname = notifyRoomname
