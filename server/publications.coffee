
# User status and profile
Meteor.publish "userStatus", ->
  Meteor.users.find { "profile.online": true },
    fields:
      'username': 1
      'profile': 1

# TODO: Improve the publication logic

Meteor.publish "datastream", ->
  Datastream.find()

Meteor.publish "docs", ->
  Documents.find()

Meteor.publish "events", ->
  Events.find()


