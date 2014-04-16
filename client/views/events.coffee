@Mapper = @Mapper || {}

# This function needs to be run before any of the event logic can happen
Mapper.processSources = ->
  # Process event choices into choice arrays
  sources = {}
  EventFields.find().forEach (field) ->
    if field.type isnt "dropdown"
      sources[field.key] = null
    else
      sources[field.key] = []
      for choice, i in field.choices
        sources[field.key].push
          text: choice
          value: i

  Mapper.sources = sources
  # Grab the fields just once ...?
  Mapper.staticFields = EventFields.find({}, {sort: {order: 1}}).fetch()

Handlebars.registerHelper "eventFields", ->
  # Process the sources if we are missing the static fields
  # Problem occured when sub ready but dependent calculation didn't run yet
  unless Mapper.staticFields
    Mapper.processSources()
  Mapper.staticFields

generateNewEvent = ->
  eventId = Random.id()

  fields = {}
  for key, val of Mapper.sources
    fields[key] = if val? then null else ""

  Meteor.call "createEvent", eventId, fields
  Session.set "selectedEvent", eventId

edit = (e) ->
  Meteor.call "editEvent", @_id
  # TODO make this less janky
  Mapper.switchTab "events"
  Session.set("scrollEvent", @_id)

# Set initial sort order on start
Meteor.startup ->
  Session.set("eventSortKey", "num")
  Session.set("eventSortOrder", 1)

Template.eventsHeader.labelClass = ->
  key = @key || "num" # FIXME: hack for the first num field
  if Session.equals("eventSortKey", key) then "label-inverse" else ""

Template.eventsHeader.iconClass = ->
  key = @key || "num" # FIXME: hack for the first num field
  if Session.equals("eventSortKey", key)
    # TODO This is inefficient. Fix it.
    if Session.get("eventSortOrder") is 1
      "icon-chevron-up"
    else
      "icon-chevron-down"
  else
    "icon-resize-vertical"

Template.eventRecords.events =
  "click .events-body tr": -> Session.set("selectedEvent", @_id)
  "click span.sorter": (e) ->
    key = $(e.target).closest("span").attr("data-key")
    sortKey = Session.get("eventSortKey")
    if sortKey? and key is sortKey
      # swap order of existing sort
      Session.set("eventSortOrder", -1 * Session.get("eventSortOrder"))
    else
      Session.set("eventSortKey", key)
      Session.set("eventSortOrder", 1)

Template.eventRecords.loaded = -> Session.equals("eventSubReady", true)

Template.eventRecords.noEvents = ->
  Events.find().count() is 0

Handlebars.registerHelper "numEventCols", ->
  # Used for rendering whole-width rows
  # Add 1 each for index, sources, map, and buttons
  EventFields.find().count() + 4

Template.eventRecords.records = ->
  key = Session.get("eventSortKey")
  return Events.find() unless key

  # Secondary sort by key prevents jumping
  #  sort[key] = Session.get("eventSortOrder") || 1 if key?
  sort = [ [key, if Session.get("eventSortOrder") is -1 then "desc" else "asc"], [ "_id", "asc" ] ]
  return Events.find {}, { sort: sort }

Template.createFooter.events =
  "click .action-event-new": (e) ->
    e.preventDefault()
    generateNewEvent()

acceptDrop = (draggable) ->
  # Don't accept drops from random pages
  return false unless Session.equals("taskView", 'events')
  event = Spark.getDataContext @ # These are the only droppables on the page
  return false unless event
  tweet = Spark.getDataContext(draggable.context)
  # Don't accept drops to the same event
  return false if $.inArray(event._id, tweet.events) >= 0
  return true

processDrop = (event, ui) ->
  event = Spark.getDataContext @
  return unless event
  tweet = Spark.getDataContext(ui.draggable.context)
  # Don't do anything if this tweet is already on this event
  return if $.inArray(event._id, tweet.events) >= 0

  target = ui.draggable.context
  parent = tweet
  while parent is tweet
    parent = Spark.getDataContext(target = target.parentNode)

  Meteor.call "dataLink", tweet._id, event._id
  # unlink from parent if it was an event
  Meteor.call "dataUnlink", tweet._id, parent._id if parent._id

Template.eventRow.rendered = ->
  $(@firstNode).droppable
    addClasses: false
    hoverClass: "success"
    tolerance: "pointer"
    accept: acceptDrop
    drop: processDrop

  if Session.equals("scrollEvent", @data._id)
    parent = $(".scroll-vertical.events-body")
    element = $(@firstNode)
    # FIXME: on IE this only works if we grab all these values beforehand
    # console.log parent.scrollTop(), element.position(), parent.height(), element.height()
    scrollTo = parent.scrollTop() + element.position().top - parent.height()/2 + element.height()/2
    parent.animate({scrollTop: scrollTo}, "slow")
    Session.set("scrollEvent", null)

Template.eventRow.events =
  "click .action-event-mapview": (e) ->
    e.preventDefault()
    # Clicking the row should already select the event
    # This automatically switches the tab view
    Mapper.switchTab "map"

  "click .action-event-locate": (e) ->
    Session.set("placingEvent", @_id)
    Mapper.switchTab("map")
    e.stopPropagation() # So the below handler can do its work

    # Cancel event placement and go back to events if clicking randomly
    $("body").one "click", ->
      if Session.get("placingEvent")
        Mapper.switchTab("events")
        Session.set("placingEvent", undefined)

  "dblclick tr": edit

Template._editCellOpen.events =
  "click .action-event-edit": edit

  "click .action-event-delete": (e) ->
    bootbox.confirm "Really delete this event? This cannot be undone!"
    , (result) =>
      Meteor.call("deleteEvent", @_id) if result

Template._editCellSelf.events =
  "click .action-event-save": (e) ->
    Meteor.call "saveEvent", @_id

###
  Rendering and helpers for individual sheet cells
###
Handlebars.registerHelper "eventCell", (context, field) ->
  obj = {
    _id: context._id
    key: field.key
    name: field.name
    value: context[field.key]
    editable: context.editor is Meteor.userId()
  }

  # Temporarily extend the field for render, but we don't have to store it in DB :)
  if field?.type is "dropdown"
    obj.textValue = Mapper.sources[field.key][obj.value]?.text if obj.value?
    return Template._eventCellSelect(obj)
  else
    return Template._eventCell(obj)

Template.eventRow.rowClass = ->
  classes = []
  classes.push("selected") if Session.equals("selectedEvent", @_id)

  if @editor is Meteor.userId()
    classes.push("info")
  else if @editor
    classes.push("warning")

  return classes.join(" ")

Template._eventCell.rendered = ->
  return unless @data.editable
  settings =
    success: (response, newValue) =>
      result = {}
      result[@data.key] = newValue
      Meteor.call "updateEvent", @data._id, result

  $(@find('div.editable:not(.editable-click)')).editable('destroy').editable(settings)
  return

Template._eventCellSelect.rendered = ->
  return unless @data.editable
  settings =
    success: (response, newValue) =>
      result = {}
      result[@data.key] = parseInt(newValue) # Make sure we store an int back in the database
      Meteor.call "updateEvent", @data._id, result
    value: @data.value
    source: Mapper.sources[@data.key]

  $(@find('div.editable:not(.editable-click)')).editable('destroy').editable(settings)
  return

Template.eventLocation.rendered = ->
  return unless @data.editor is Meteor.userId()
  settings =
    success: (response, newValue) =>
      Meteor.call "updateEvent", @data._id, { location: newValue }
    value: @data.location

  $(@find('div.editable:not(.editable-click)')).editable('destroy').editable(settings)
  return

Template.eventLocation.editable = -> @editor is Meteor.userId()

Handlebars.registerHelper "editCell", ->
  me = Meteor.userId()
  if @editor is me
    return Template._editCellSelf @
  else if @editor?
    return Template.userPill(Meteor.users.findOne(@editor)) + " is editing"
  else
    return Template._editCellOpen @

Template.eventVoting.rendered = ->
  eventId = @data._id
  $(@firstNode).popover
    html: true
    placement: "left"
    trigger: "hover"
    container: @firstNode # Hovering over the popover should hold it open
    content: ->
      Meteor.render ->
        Template.eventVotePopup Events.findOne(eventId, fields: {votes: 1})

Template.eventVoting.events =
  "click .action-event-upvote": -> Meteor.call "voteEvent", @_id
  "click .action-event-unvote": -> Meteor.call "unvoteEvent", @_id

Template.eventVoting.badgeClass = -> if @votes?.length > 0 then "badge-success" else "badge-default"
Template.eventVoting.numVotes = -> @votes?.length || 0

Template.eventVotePopup.anyVotes = -> @votes?.length > 0
Template.eventVotePopup.iVoted = ->
  userId = Meteor.userId()
  return userId && _.contains(@votes, userId)
