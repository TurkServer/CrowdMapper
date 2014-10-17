Template.notifications.helpers
  notifications: ->
    return Notifications.find {},
      # show most recent first
      sort: {timestamp: -1}

  glowClass: ->
    if Notifications.find().count() > 0 then "glowing" else ""

  notificationCount: ->
    return Notifications.find().count()

  notificationTemplate: ->
    switch @type
      when "invite" then Template._inviteNotification
      when "mention" then Template._mentionNotification
      else null

notifyEvents =
  'click a': (e) ->
    e.preventDefault()
    Session.set("room", this.room)
    Meteor.call "readNotification", this._id
      
Template._inviteNotification.events(notifyEvents)
Template._mentionNotification.events(notifyEvents)
  
notifyUsername = ->
  Meteor.users.findOne(@sender)?.username
  
notifyRoomname = ->
  ChatRooms.findOne(@room)?.name

notificationHelpers = {
  username: notifyUsername
  roomName: notifyRoomname
}

Template._inviteNotification.helpers(notificationHelpers)
Template._mentionNotification.helpers(notificationHelpers)
