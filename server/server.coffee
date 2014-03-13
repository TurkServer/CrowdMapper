###
  TurkServer-ed publications
  All of these publications check for grouping, except notifications
###

# User status and username
Meteor.publish "userStatus", ->
  Meteor.users.find {}, # All users (in my group)
    fields:
      username: 1
      "status.online": 1 # Don't publish random other status fields

# TODO we can publish deleted things for admin for watching later.
# Publish non-deleted events, docs, and events

Meteor.publish "datastream", ->
  Datastream.find(hidden: {$exists: false})

Meteor.publish "docs", ->
  Documents.find(deleted: {$exists: false})

Meteor.publish "events", ->
  Events.find(deleted: {$exists: false})

###
  These are not indexed by TurkServer
###
Notifications._ensureIndex
  user: 1

Meteor.publish 'notifications', ->
  # Only publish unread notifications for this user
  Notifications.find
    user: this.userId
    read: {$exists: false}

###
  Methods
###

Meteor.methods
  "finishTutorial": ->
    if TurkServer.treatment() is "recruiting"
      TurkServer.finishExperiment()
