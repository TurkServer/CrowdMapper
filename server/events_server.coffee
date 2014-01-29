# Publish all event fields
Meteor.publish "eventFieldData", ->
  sub = this

  EventFields.find().forEach (doc) ->
    sub.added("eventfields", doc._id, doc)

  sub.ready()

# Create an index on events to delete editors who piss off
# No need to index non-editor events
Events._ensureIndex {editor: 1}, {sparse: true}

TurkServer.onDisconnect ->
  Events.update { editor: @userId },
    $unset: { editor: null }
  , multi: true
