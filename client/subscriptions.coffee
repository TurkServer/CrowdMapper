# TODO move these to be router controlled

fieldSub = Meteor.subscribe("eventFieldData")

Deps.autorun ->
  return unless fieldSub.ready()
  Mapper.processSources()
  @stop()

Meteor.subscribe("chatrooms")
# Chat messages are subscribed to individually

Meteor.subscribe("userStatus")

Meteor.subscribe("datastream")
Meteor.subscribe("docs")

Meteor.subscribe("events")

Meteor.subscribe("notifications")

