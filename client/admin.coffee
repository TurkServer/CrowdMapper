Template.adminControls.events
  "change input": (e, t) ->
    Session.set("adminShowDeleted", e.target.checked)

Template.adminControls.showDeleted = -> Session.equals("adminShowDeleted", true)

Template.adminControls.remainingData = -> Datastream.find({
    $or: [ { events: null }, { events: {$size: 0} } ],
    hidden: null
  }).count()

Template.adminControls.hiddenData = -> Datastream.find({ hidden: true }).count()

Template.adminControls.attachedData = -> Datastream.find({
    "events.0": $exists: true
  }).count()

Template.adminControls.createdEvents = -> Events.find({deleted: null}).count()

Template.adminControls.deletedEvents = -> Events.find({deleted: true}).count()
