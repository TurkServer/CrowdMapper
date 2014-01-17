# User status and username
Meteor.publish "userStatus", ->
  Meteor.users.find {}, # All users (in my group)
    fields:
      username: 1
      status: 1

# TODO: Improve the publication logic

Meteor.publish "datastream", ->
  Datastream.find()

Meteor.publish "docs", ->
  Documents.find()

Meteor.publish "events", ->
  Events.find()

# TODO: index notifications

Meteor.publish 'notifications', ->
  # Only publish unread notifications for this user
  Notifications.find
    user: this.userId
    read: {$exists: false}
