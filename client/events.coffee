
Template.events.eventRecords = ->
  Events.find {}

edit = (e) ->
  Events.update @_id,
    $set: { editor: Meteor.userId() }

epsg4326 = new OpenLayers.Projection("EPSG:4326")
epsg900913 = new OpenLayers.Projection("EPSG:900913")

Template.events.events =
  "click a.button-newevent": (e) ->
    e.preventDefault()

    Events.insert
      province: "empty",
      region: "empty",
      type: "empty",
      description: "empty",
      sources: "empty"

Template.eventRow.events =
  "click .button-locate": (e) ->
    # In the future, bring to map edit interface
    Events.update @_id,
      $set:
        location: [13410000, 1104000] # in the ocean near philippines

  "click a.button-delete": (e) ->
    Events.remove @_id

  "dblclick tr": edit
  "click a.button-edit": edit

  # Blur on enter key
  "keydown div[data-ref]": (e) ->
    return unless e.keyCode == 13
    e.preventDefault()
    $(e.target).blur()

  "blur div[data-ref]": (e) ->
    el = $(e.target)
    val = {}
    val[el.attr("data-ref")] = el.text()
    Events.update @_id,
      $set: val

  "click a.button-save": (e) ->
    context = $(e.target).closest("tr")
    Events.update @_id,
      $unset: { editor: 1 }

Template.eventRow.editing = -> @editor?

Template.eventRow.iAmEditing = -> @editor is Meteor.userId()

Template.eventRow.formatLocation = ->
  point = new OpenLayers.Geometry.Point(@location[0], @location[1])
  point.transform(epsg900913, epsg4326)
  point.y.toFixed(2) + "," + point.x.toFixed(2)
