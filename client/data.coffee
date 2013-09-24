@ChatUsers = new Meteor.Collection("chatusers")

Meteor.methods
  createEvent: (eventId, fields) ->
    obj = {
      _id: eventId
      sources: []
    # location: undefined
    }

    _.extend(obj, fields)

    Events.insert(obj)
