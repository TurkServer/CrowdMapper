Template.notifications.notifications = ->
  return Notifications.find {}
    # TODO sort in decreasing order
    # sort: {timestamp: -1}

Template.notifications.notificationCount = ->
  return Notifications.find().count()

Template.notifications.renderNotification = ->
  switch @type
    when "invite" then Template._inviteNotification @
    when "mention" then Template._mentionNotification @

notifyEvents =
  'click a': (e) ->
    e.preventDefault()    
    Notifications.update this._id,
      $set: {read: true}
    Session.set("room", this.room)
      
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
