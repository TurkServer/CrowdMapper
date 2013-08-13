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

generateNewEvent = ->
  # TODO maybe switch to Mongo IDs at some point
  eventId = Random.id()

  fields = {}
  for key, val of sources
    fields[key] = if val? then null else ""

  Meteor.call "createEvent", eventId, fields

edit = (e) ->
  Meteor.call "editEvent", @_id

Template.events.events =
  "click .action-event-new": (e) ->
    e.preventDefault()

    generateNewEvent()

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

Template.emptyRow.numCols = ->
  # Add 1 each for sources, map, and buttons
  # TODO kinda hacky and not robust
  Meteor.settings.public.events.length + 3

Template.events.eventRecords = ->
  key = Session.get("eventSortKey")
  return Events.find() unless key

  # Secondary sort by key prevents jumping
  #  sort[key] = Session.get("eventSortOrder") || 1 if key?
  sort = [ [key, if Session.get("eventSortOrder") is -1 then "desc" else "asc"], [ "_id", "asc" ] ]
  return Events.find {}, { sort: sort }

Template.events.iconClass = ->
  if Session.equals("eventSortKey", @key)
    # TODO This is inefficient. Fix it.
    if Session.get("eventSortOrder") is 1
      "icon-chevron-up"
    else
      "icon-chevron-down"
  else
    "icon-resize-vertical"

Template.eventRow.rendered = ->
  data = @data
  $(@firstNode).droppable
    addClasses: false
    hoverClass: "info"
    tolerance: "pointer"
    drop: (event, ui) ->
      tweet = Spark.getDataContext(ui.draggable.context)

      Meteor.call "dataLink", tweet._id, data._id

Template.eventRow.events =
  "click .action-event-mapview": (e) ->
    e.preventDefault()
    # TODO give the proper active style at the top
    Session.set("taskView", "map")

    Mapper.selectEvent @_id

  "click .action-event-locate": (e) ->
    # In the future, bring to map edit interface
    Events.update @_id,
      $set:
        location: [13410000, 1104000] # in the ocean near philippines

    Session.set("taskView", "map")
    # TODO show a message to do something with this
    # TODO does this require a flush?
    Mapper.selectEvent @_id

  "dblclick tr": edit
  "click .action-event-edit": edit

  "click .action-event-delete": (e) ->
    bootbox.confirm "Really delete this event? This cannot be undone!"
    , (result) =>
      Meteor.call("deleteEvent", @_id) if result

  "click .action-event-save": (e) ->
    Events.update @_id,
      $unset: { editor: 1 }

Handlebars.registerHelper "eventFields", ->
  Meteor.settings.public.events

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

Handlebars.registerHelper "cellEditable", -> @editor is Meteor.userId()

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
