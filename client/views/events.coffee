
Template.events.eventRecords = ->
  Events.find {}

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
      sources: ""

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

Template.eventRow.formatLocation = ->
  point = new OpenLayers.Geometry.Point(@location[0], @location[1])
  point.transform(epsg900913, epsg4326)
  point.y.toFixed(2) + ",<br>" + point.x.toFixed(2)

Handlebars.registerHelper "eventCell", (context, field, editable) ->
  return new Handlebars.SafeString(
    Template._eventCell
      _id: context._id
      field: field
      value: context[field]
      editable: editable
  )

Template._eventCell.rendered = ->
  return unless @data.editable
  $(@find('div.editable:not(.editable-click)')).editable('destroy').editable
    success: (response, newValue) =>
      val = {}
      val[@data.field] = newValue
      Events.update @data._id,
        $set: val
