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

  sendChat: (roomId, message) ->
    # Do nothing on client side, wait for server ack
    return if @isSimulation
