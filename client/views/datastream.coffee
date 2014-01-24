
Template.datastream.data = ->
  Datastream.find({}) # , sort: {_id: 1}) # Natural order is insertion

Template.datastream.visible = ->
  # Order in which we register reactive dependencies with short-circuit boolean matters here for efficiency
  if @events? and @events.length > 0
    return false # Session.equals("data-tagged", true)
  else if @hidden
    return false # Session.equals("data-hidden", true)
  else
    return true # Session.equals("data-unfiltered", true)

Template.datastream.events =
  "click .action-data-hide": ->
    Meteor.call "dataHide", @_id

dragHelper = ->
  # Make sure we are on events
  Mapper.switchTab("events")
  # Set explicit width on the clone
  currentWidth = $(this).width()
  return $(this).clone().width(currentWidth)

Template.dataItem.rendered = ->
  # Only visible elements are rendered in the #each helper so no optimization to do here
  $(@firstNode).draggable
    addClasses: false
    # TODO: Allow text selection on parts of tweet
    # cancel: ".data-text"
    # containment: "window"
    cursorAt: { top: 0, left: 0 }
    distance: 5
    revert: "invalid"
    scroll: false
    zIndex: 1000
    # Make it really obvious where to drop these
    start: Mapper.highlightEvents
    stop: Mapper.unhighlightEvents
    helper: dragHelper

  if Session.equals("scrollTweet", @data._id)
    parent = $(".scroll-vertical.data-body")
    element = $(@firstNode)
    scrollTo = parent.scrollTop() + element.position().top - parent.height()/2 + element.height()/2;
    parent.animate({scrollTop: scrollTo}, "slow")
    Session.set("scrollTweet", null)

Template.dataItem.events =
  "click .data-cell": (e) ->
    Session.set("selectedTweet", @_id)

Template.dataItem.selected = ->
  if Session.equals("selectedTweet", @_id) then "selected" else ""
