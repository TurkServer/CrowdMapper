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
  Mapper.selectEvent(eventId)

edit = (e) ->
  Meteor.call "editEvent", @_id
  Mapper.switchTab "events"
  Mapper.scrollToEvent(@_id)

# Set initial sort order on start
Meteor.startup ->
  Session.set("eventSortKey", "num")
  Session.set("eventSortOrder", 1)

Template.eventsHeader.labelClass = ->
  key = @key || "num" # FIXME: hack for the first num field
  if Session.equals("eventSortKey", key) then "inverse" else "default"

Template.eventsHeader.iconClass = ->
  key = @key || "num" # FIXME: hack for the first num field
  if Session.equals("eventSortKey", key)
    # TODO This is inefficient. Fix it.
    if Session.get("eventSortOrder") is 1
      "chevron-up"
    else
      "chevron-down"
  else
    "resize-vertical"

Template.eventRecords.events =
  "click .events-body tr": (e, t) ->
    Mapper.selectEvent(@_id)
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
  event = UI.getElementData @ # These are the only droppables on the page
  return false unless event
  tweet = UI.getElementData(draggable.context)
  # Don't accept drops to the same event
  return false if $.inArray(event._id, tweet.events) >= 0
  return true

processDrop = (event, ui) ->
  event = UI.getElementData @
  return unless event
  tweet = UI.getElementData(ui.draggable.context)
  # Don't do anything if this tweet is already on this event
  return if $.inArray(event._id, tweet.events) >= 0

  target = ui.draggable.context
  parent = tweet
  while parent is tweet
    parent = UI.getElementData(target = target.parentNode)

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

# This is used in both table row and map popup
Template.editCell.otherEditorUser = ->
  if @editor? and @editor isnt Meteor.userId()
    return Meteor.users.findOne(@editor)
  return null

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
Template.eventRow.rowClass = ->
  if @editor is Meteor.userId()
    "info"
  else if @editor
    "warning"
  else
    ""

Template.eventRow.eventCell = ->
  if this?.type is "dropdown"
    return Template.eventCellSelect
  else
    return Template.eventCellText

Template.eventRow.buildData = (context, field) ->
  obj = {
    _id: context._id
    key: field.key
    name: field.name
    value: context[field.key]
    editable: context.editor is Meteor.userId()
  }

  if field?.type is "dropdown" and obj.value?
    obj.textValue = Mapper.sources[field.key][obj.value]?.text

  return obj

# Partial implementation of the code from http://stackoverflow.com/a/23144211/586086
# Except, we don't need to update the form content because we are the only one editing
# Autotext is disabled so that 'Empty' is never written and breaking reactivity

Template.eventCellTextEditable.rendered = ->
  return unless @data.editable
  @$('div.editable').editable
    display: ->
    success: (response, newValue) =>
      result = {}
      result[@data.key] = newValue
      Meteor.call "updateEvent", @data._id, result
      return true
  return

Template.eventCellSelectEditable.rendered = ->
  return unless @data.editable
  @$('div.editable').editable
    display: ->
    success: (response, newValue) =>
      result = {}
      result[@data.key] = parseInt(newValue) # Make sure we store an int back in the database
      Meteor.call "updateEvent", @data._id, result
      return true
    value: @data.value
    source: Mapper.sources[@data.key]
  return

Template.eventLocation.editable = -> @editor is Meteor.userId()

Template.eventLocationEditable.rendered = ->
  return unless @data.editor is Meteor.userId()
  @$('div.editable').editable
    display: ->
    success: (response, newValue) =>
      Meteor.call "updateEvent", @data._id, { location: newValue }
      return true
    value: @data.location
  return

Template.eventVoting.rendered = ->
  eventId = @data._id
  $(@firstNode).popover
    html: true
    placement: "left"
    trigger: "hover"
    container: @firstNode # Hovering over the popover should hold it open
    content: ->
      # TODO Make this properly reactive
      UI.toHTML Template.eventVotePopup.extend data: -> Events.findOne(eventId, fields: {votes: 1})

Template.eventVoting.events =
  "click .action-event-upvote": -> Meteor.call "voteEvent", @_id
  "click .action-event-unvote": -> Meteor.call "unvoteEvent", @_id

Template.eventVoting.badgeClass = -> if @votes?.length > 0 then "alert-success" else ""
Template.eventVoting.numVotes = -> @votes?.length || 0

Template.eventVotePopup.anyVotes = -> @votes?.length > 0
Template.eventVotePopup.iVoted = ->
  userId = Meteor.userId()
  return userId && _.contains(@votes, userId)
