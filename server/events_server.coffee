# Create an index on events to delete editors who piss off
Events._ensureIndex
  editor: 1

UserStatus.on "sessionLogout", (userId, _) ->
  Events.update { editor: userId },
    $unset: { editor: null }
  , multi: true

# Create an index on event sequencing for efficient lookup
Events._ensureIndex
  num: 1

maxEventIdx = null

Meteor.startup ->
  maxEventIdx = Events.findOne({}, sort: {num: -1})?.num || 0

  # Populate numbers for events that don't have numbers
  Events.find(num: {$exists: false}).forEach (event) ->
    Events.update(event._id, $set: { num: ++maxEventIdx } )

Meteor.methods
  createEvent: (eventId, fields) ->
    obj = {
      _id: eventId
      sources: []
    # location: undefined
    }

    _.extend(obj, fields)
    # Increment number for this event
    obj.num = ++maxEventIdx

    Events.insert(obj)
