###
  TurkServer-ed publications
  All of these publications check for grouping, except notifications
###

userFields = {
  fields: {
    username: 1
    status: 1
  }
}

# User status and username
Meteor.publish "userStatus", ->
  ###
    The status field below should really be "status.online" to not publish random other status fields
    But we need to leave it at status because otherwise we will be missing fields on the merge.
    https://github.com/meteor/meteor/issues/998
  ###
  Meteor.users.find({}, userFields) # All users (in my group)

# Publish all events, docs, and events, including deleted - filtering is done on the client
# This means admins can see deleted items easily, and they still work in chat

Meteor.publish "datastream", -> Datastream.find()

Meteor.publish "docs", -> Documents.find()

Meteor.publish "events", -> Events.find()

Meteor.publish 'notifications', ->
  # Only publish unread notifications for this user (in this instance)
  Notifications.find
    user: this.userId
    read: {$exists: false}

# Alternate admin publication for watching, that does not block TurkServer
Meteor.publish "adminWatch", (instance) ->
  return [] unless Meteor.users.findOne(@userId)?.admin
  check(instance, String)

  # Hack to make sure we get both current users and past ones
  # TODO does not update as group is filling
  exp = Experiments.findOne(instance)
  treatments = exp?.treatments || []
  users = exp?.users || []

  return Partitioner.directOperation ->
    [
      # Group and treatment data
      Experiments.find(instance),
      Treatments.find({name: $in : treatments})
      # Experiment data
      ChatRooms.find({_groupId: instance}),
      Meteor.users.find({$or: [
        { _id: $in: users },
        { group: instance }
      ]}, userFields),
      Datastream.find({_groupId: instance}),
      Documents.find({_groupId: instance}),
      Events.find({_groupId: instance}),
    ]

###
  Methods
###

Meteor.methods
  "finishTutorial": ->
    exp = TurkServer.Instance.currentInstance()
    # If finish button is mashed, this may not exist.
    unless exp?
      Meteor._debug("Finish tutorial: may have already finished for ", Meteor.userId())
      return

    if exp.treatment()?.tutorialEnabled
      # Don't accidentally teardown something that isn't the tutorial
      exp.teardown()

    return

  "getMapperData": (groupId) ->
    TurkServer.checkAdmin()

    instance =  Experiments.findOne(groupId)

    roomIds = Partitioner.directOperation ->
      ChatRooms.find(_groupId: groupId).map (room) -> room._id

    users = Meteor.users.find(_id: $in: instance.users).fetch()
    logs = Logs.find({_groupId: groupId}, {sort: {_timestamp: 1}}).fetch()
    chat = ChatMessages.find({room: $in: roomIds}, {sort: {timestamp: 1}}).fetch()

    return {instance, users, logs, chat}

