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

# Publish all events, docs, and events, including deleted - filtering is done on the client
# This means admins can see deleted items easily, and they still work in chat

Meteor.publish "datastream", -> Datastream.find()

Meteor.publish "docs", -> Documents.find()

Meteor.publish "events", -> Events.find()

# TODO old stuff, can be removed later.
try
  Notifications._dropIndex
    user: 1

Meteor.publish 'notifications', ->
  # Only publish unread notifications for this user (in this instance)
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
