Template.datastream.loaded = -> Session.equals("dataSubReady", true)

# We want events to exist and events.length > 0 to display
# So we get all docs where events either doesn't exist or it's of size 0
dataSelector = {
  $or: [
    { events: {$exists: false} },
    { events: {$size: 0} }
  ]
}

Template.dataList.data = ->
  selector = if TurkServer.isAdmin()
    dataSelector # Ignoring hidden values
  else
    _.extend({}, dataSelector, { hidden: {$exists: false} })
  return Datastream.find(selector, sort: {num: 1}) # Sort in increasing insertion order


Template.dataList.rendered = ->
  # See reference implementation at packages/ui/domrange.js
  parent = @firstNode
  parent._uihooks =
    insertElement: (node, next) ->
      parent.insertBefore(node, next)
    moveElement: (node, next) ->
      parent.insertBefore(node, next)
    removeElement: (node) ->
      $node = $(node)
      # We need to compute these before the fadeOut, which adds display: none
      nodeTop = node.offsetTop
      nodeHeight = $node.height()
      parentHeight = $(parent).height()
      # Fade out the node, and when completed remove it and adjust the scroll height
      $node.fadeOut "slow", ->
        $(this).remove() # equiv to parent.removeChild(node) or $node.remove()
        # Adjust scroll position around the removed element, if it was above the viewport
        if nodeTop < parent.scrollTop + parentHeight/2
          parent.scrollTop = parent.scrollTop - nodeHeight
      return

Template.dataList.events =
  "click .action-data-hide": ->
    Meteor.call "dataHide", @_id

dragHelper = ->
  # Make sure we are on events
  Mapper.switchTab("events")
  # Set explicit width on the clone
  currentWidth = $(this).width()
  return $(this).clone().width(currentWidth)

dragProps =
  addClasses: false
  # cancel: ".data-text"
  # containment: "window"
  cursorAt: { top: 0, left: 0 }
  distance: 5
  handle: ".label" # the header
  helper: dragHelper
  revert: "invalid"
  scroll: false
  # Make it really obvious where to drop these
  start: Mapper.highlightEvents
  stop: Mapper.unhighlightEvents
  zIndex: 1000

Template.dataItem.rendered = ->
  # Only visible elements are rendered in the #each helper so no optimization to do here
  $(@firstNode).draggable dragProps

Template.dataItem.events =
  "click .data-cell": (e, t) -> Mapper.selectData(@_id)

Template.dataItem.hidden = -> if @hidden then "data-cell-hidden" else ""
