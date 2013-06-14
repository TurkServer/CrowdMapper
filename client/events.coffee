
Template.events.eventRecords = ->
  Events.find {}

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

  "click a.button-edit": (e) ->
    Events.update @_id,
      $set: { editor: Meteor.userId() }

Template.eventRow.editing = -> @editor?

Template.eventRow.iAmEditing = -> @editor is Meteor.userId()
