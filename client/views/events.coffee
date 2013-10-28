@Mapper = @Mapper || {}

# Process event choices into choice arrays
sources = {}
for field in Meteor.settings.public.events
  if field.type isnt "dropdown"
    sources[field.key] = null
  else
    sources[field.key] = []
    for choice, i in field.choices
      sources[field.key].push
        text: choice
        value: i

@Mapper.sources = sources

# Fix the order of event fields
# TODO get this from the server sometime in the future
eventFields = []
eventDefs = Meteor.settings.public.events
# Order: type, description, region, province
eventFields.push eventDefs[2]
eventFields.push eventDefs[3]
eventFields.push eventDefs[0]
eventFields.push eventDefs[1]

Handlebars.registerHelper "eventFields", -> eventFields

generateNewEvent = ->
  # TODO maybe switch to Mongo IDs at some point
  eventId = Random.id()

  fields = {}
  for key, val of sources
    fields[key] = if val? then null else ""

  Meteor.call "createEvent", eventId, fields

edit = (e) ->
  Meteor.call "editEvent", @_id

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

Template.events.events =
  "click tr": (e) ->
    Session.set("selectedEvent", @_id)
  "click span.sorter": (e) ->
    key = $(e.target).closest("span").attr("data-key")
    sortKey = Session.get("eventSortKey")
    if sortKey? and key is sortKey
      # swap order of existing sort
      Session.set("eventSortOrder", -1 * Session.get("eventSortOrder"))
    else
      Session.set("eventSortKey", key)
      Session.set("eventSortOrder", 1)

Template.events.noEvents = ->
  Events.find().count() is 0

Handlebars.registerHelper "numEventCols", ->
  # Add 1 each for sources, map, and buttons
  # TODO kinda hacky and not robust
  Meteor.settings.public.events.length + 4

Template.events.eventRecords = ->
  key = Session.get("eventSortKey")
  return Events.find() unless key

  # Secondary sort by key prevents jumping
  #  sort[key] = Session.get("eventSortOrder") || 1 if key?
  sort = [ [key, if Session.get("eventSortOrder") is -1 then "desc" else "asc"], [ "_id", "asc" ] ]
  return Events.find {}, { sort: sort }

Template.createRow.events =
  "click .action-event-new": (e) ->
    e.preventDefault()
    generateNewEvent()

acceptDrop = ->
  # Don't accept drops from random pages
  Session.equals("taskView", 'events')

Template.eventRow.rendered = ->
  data = @data
  $(@firstNode).droppable
    addClasses: false
    hoverClass: "info"
    tolerance: "pointer"
    accept: acceptDrop
    drop: processDrop = (event, ui) ->
      tweet = Spark.getDataContext(ui.draggable.context)
      # Don't do anything if this tweet is already on this event
      return if $.inArray(data._id, tweet.events) >= 0

      target = ui.draggable.context
      parent = tweet
      while parent is tweet
        parent = Spark.getDataContext(target = target.parentNode)

      Meteor.call "dataLink", tweet._id, data._id
      # unlink from parent if it was an event
      Meteor.call "dataUnlink", tweet._id, parent._id if parent._id

  if Session.equals("scrollEvent", @data._id)
    parent = $(".scroll-vertical.events-body")
    element = $(@firstNode)
    scrollTo = parent.scrollTop() + element.position().top - parent.height()/2 + element.height()/2;
    parent.animate({scrollTop: scrollTo}, "slow")
    Session.set("scrollEvent", null)

Template.eventRow.events =
  "click .action-event-mapview": (e) ->
    e.preventDefault()

    # This automatically switches the tab view
    Mapper.switchTab "map"
    Mapper.selectEvent @_id

  "click .action-event-locate": (e) ->
    # In the future, bring to map edit interface
    Events.update @_id,
      $set:
        location: [13410000, 1104000] # in the ocean near philippines

    Mapper.switchTab "map"
    # TODO show a message to do something with this
    # TODO does this require a flush? Doesn't seem like it...
    Mapper.selectEvent @_id

  "dblclick tr": edit

Template._editCellOpen.events =
  "click .action-event-edit": edit

  "click .action-event-delete": (e) ->
    bootbox.confirm "Really delete this event? This cannot be undone!"
    , (result) =>
      Meteor.call("deleteEvent", @_id) if result

Template._editCellSelf.events =
  "click .action-event-save": (e) ->
    Events.update @_id,
      $unset: { editor: 1 }

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
    obj.textValue = sources[field.key][obj.value]?.text if obj.value?
    return new Handlebars.SafeString Template._eventCellSelect(obj)
  else
    return new Handlebars.SafeString Template._eventCell(obj)

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
      Events.update @data._id,
        $set: result

  $(@find('div.editable:not(.editable-click)')).editable('destroy').editable(settings)

Template._eventCellSelect.rendered = ->
  return unless @data.editable
  settings =
    success: (response, newValue) =>
      result = {}
      result[@data.key] = newValue
      Events.update @data._id,
        $set: result
    value: @data.value
    source: sources[@data.key]

  $(@find('div.editable:not(.editable-click)')).editable('destroy').editable(settings)

Handlebars.registerHelper "editCell", ->
  me = Meteor.userId()
  if @editor is me
    return new Handlebars.SafeString Template._editCellSelf @
  else if @editor?
    return new Handlebars.SafeString Template._editCellOther @
  else
    return new Handlebars.SafeString Template._editCellOpen @
