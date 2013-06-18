
Template.events.eventRecords = ->
  Events.find {}

edit = (e) ->
  Events.update @_id,
    $set: { editor: Meteor.userId() }

Template.events.events =
  "click a.button-newevent": (e) ->
    e.preventDefault()

    Events.insert
      province: "empty",
      region: "empty",
      type: "empty",
      description: "empty",
      sources: "empty"

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
