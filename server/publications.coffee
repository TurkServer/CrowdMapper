# All of these publications check for grouping, except notifications

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

# This is not indexed by TurkServer
Notifications._ensureIndex
  user: 1

Meteor.publish 'notifications', ->
  # Only publish unread notifications for this user
  Notifications.find
    user: this.userId
    read: {$exists: false}
