# Enable all toggles when app starts
Meteor.startup ->
  Session.set("data-unfiltered", true)
  Session.set("data-tagged", true)
  Session.set("data-hidden", true)

Template.datastream.data = ->
  Datastream.find({}, sort: {_id: 1})

Template.datastream.visible = ->
  # Order in which we register reactive dependencies with short-circuit boolean matters here for efficiency
  if @events? and @events.length > 0
    return Session.equals("data-tagged", true)
  else if @hidden
    return Session.equals("data-hidden", true)
  else
    return Session.equals("data-unfiltered", true)

Template.datastream.events =
  "click .action-data-hide": ->
    Meteor.call "dataHide", @_id

  "click .action-data-unhide": ->
    Meteor.call "dataUnhide", @_id

Template.dataToggle.unfiltered = -> Session.equals("data-unfiltered", true)
Template.dataToggle.tagged = -> Session.equals("data-tagged", true)
Template.dataToggle.hidden = -> Session.equals("data-hidden", true)

Template.dataToggle.events =
  "click button": (e) ->
    key = "data-" + e.target.getAttribute("data-show")
    value = Session.get(key)
    Session.set(key, !value)

Template.datastream.dataItem = ->
  if @events? and @events.length > 0
    return new Handlebars.SafeString Template._dataItemTagged @
  else if @hidden
    return new Handlebars.SafeString Template._dataItemHidden @
  else
    return new Handlebars.SafeString Template._dataItemNormal @

dataItemRender = ->
  # Only visible elements are rendered in the #each helper so no optimization to do here
  $(@firstNode).draggable
    addClasses: false
    # containment: "window"
    cursorAt: { top: 0, left: 0 }
    distance: 5
    revert: "invalid"
    scroll: false
    zIndex: 1000

    helper: ->
      # Set explicit width on the clone
      currentWidth = $(this).width()
      return $(this).clone().width(currentWidth)

Template._dataItemTagged.rendered = dataItemRender
Template._dataItemNormal.rendered = dataItemRender
Template._dataItemHidden.rendered = dataItemRender

Template._dataItemTagged.numEvents = -> @events.length
