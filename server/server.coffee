###
  TurkServer-ed publications
  All of these publications check for grouping, except notifications
###

# User status and username
Meteor.publish "userStatus", ->
  ###
    The status field below should really be "status.online" to not publish random other status fields
    But we need to leave it at status because otherwise we will be missing fields on the merge.
    https://github.com/meteor/meteor/issues/998
  ###
  Meteor.users.find {}, # All users (in my group)
    fields:
      username: 1
      status: 1

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
    exp = TurkServer.Instance.currentInstance()
    if exp.treatment()?.tutorialEnabled
      exp.teardown()
