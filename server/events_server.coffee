# Publish all event fields
Meteor.publish "eventFieldData", ->
  sub = this

  EventFields.find().forEach (doc) ->
    sub.added("eventfields", doc._id, doc)

  sub.ready()

# Create an index on events to delete editors who piss off
Events._ensureIndex
  editor: 1

TurkServer.onDisconnect ->
  Events.update { editor: @userId },
    $unset: { editor: null }
  , multi: true

Meteor.methods
  createEvent: (eventId, fields) ->
    obj = {
      _id: eventId
      sources: []
    # location: undefined
    }

    _.extend(obj, fields)
    # Increment number based on highest numbered event
    maxEventIdx = Events.findOne({}, sort: {num: -1})?.num || 0
    obj.num = maxEventIdx + 1

    Events.insert(obj)
