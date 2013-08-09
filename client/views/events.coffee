
edit = (e) ->
  Events.update @_id,
    $set: { editor: Meteor.userId() }
  , {}, (err) ->

#    row = $(e.target).closest("tr")
#
#    row.popover(
#      placement: "left"
#      content: "Click a cell to edit"
#      trigger: "hover"
#    )

epsg4326 = null
epsg900913 = null

# Initialize these after page loaded
Template.events.created = ->
  epsg4326 = new OpenLayers.Projection("EPSG:4326")
  epsg900913 = new OpenLayers.Projection("EPSG:900913")

Template.events.events =
  "click a.button-newevent": (e) ->
    e.preventDefault()

    Events.insert
      editor: Meteor.userId()
      province: "",
      region: "",
      type: "",
      description: "",
      sources: []

  "click span.sorter": (e) ->
    key = $(e.target).closest("span").attr("data-key")
    sortKey = Session.get("eventSortKey")
    if sortKey? and key is sortKey
      # swap order of existing sort
      Session.set("eventSortOrder", -1 * Session.get("eventSortOrder"))
    else
      Session.set("eventSortKey", key)
      Session.set("eventSortOrder", 1)

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
    hoverClass: "success"
    tolerance: "pointer"
    drop: (event, ui) ->
      tweet = Spark.getDataContext(ui.draggable.context)

      Events.update data._id,
        $addToSet: { sources: tweet._id }

Template.eventRow.events =
  "click .button-locate": (e) ->
    # In the future, bring to map edit interface
    Events.update @_id,
      $set:
        location: [13410000, 1104000] # in the ocean near philippines

  "click .button-delete": (e) ->
    bootbox.confirm "Really delete this event? This cannot be undone!"
    , (result) =>
      Events.remove @_id if result

  "dblclick tr": edit
  "click .button-edit": edit

  "click .button-save": (e) ->
    Events.update @_id,
      $unset: { editor: 1 }

Template.eventRow.editing = -> @editor?

Template.eventRow.editorUser = -> Meteor.users.findOne(@editor)

Template.eventRow.iAmEditing = -> @editor is Meteor.userId()

Handlebars.registerHelper "formatLocation", ->
  point = new OpenLayers.Geometry.Point(@location[0], @location[1])
  point.transform(epsg900913, epsg4326)
  point.x.toFixed(2) + ", " + point.y.toFixed(2)

Handlebars.registerHelper "eventFields", ->
  Meteor.settings.public.events

# Process event choices into choice arrays
sources = {}
for field in Meteor.settings.public.events
  continue if field.type isnt "dropdown"
  sources[field.key] = []
  for choice in field.choices
    sources[field.key].push
      text: choice
      value: choice

###
  Rendering and helpers for individual sheet cells
###
Handlebars.registerHelper "eventCell", (context, field) ->
  obj =
    _id: context._id
    value: context[field.key]
    editable: context.editor is Meteor.userId()

  $.extend(obj, field)

  if field?.type is "dropdown"
    return new Handlebars.SafeString Template._eventCellSelect(obj)
  else
    return new Handlebars.SafeString Template._eventCell(obj)

Template._eventCell.rendered = ->
  return unless @data.editable
  settings =
    success: (response, newValue) =>
      val = {}
      val[@data.key] = newValue
      Events.update @data._id,
        $set: val

  $(@find('div.editable:not(.editable-click)')).editable('destroy').editable(settings)

Template._eventCellSelect.rendered = ->
  return unless @data.editable
  settings =
    success: (response, newValue) =>
      val = {}
      val[@data.key] = newValue
      Events.update @data._id,
        $set: val
    value: @data.value
    source: sources[@data.key]

  $(@find('div.editable:not(.editable-click)')).editable('destroy').editable(settings)

Template.tweetIcon.rendered = ->
  $(@firstNode).popover
    html: true
    placement: "top"
    trigger: "hover"
    content: =>
      Datastream.findOne(@data).text
