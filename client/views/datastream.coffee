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
  selector = if TurkServer.isAdmin() and Session.equals("adminShowDeleted", true)
    # Ignoring just tagged events values
    dataSelector
  else
    _.extend({}, dataSelector, { hidden: {$exists: false} })
  return Datastream.find(selector, sort: {num: 1}) # Sort in increasing insertion order

Template.dataList.rendered = ->
  # See reference implementation at packages/ui/domrange.js
  # TODO update this for final API of UI hooks
  parent = @firstNode
  $parent = $(parent)

  parent._uihooks =
    insertElement: (node, next) ->
      parent.insertBefore(node, next)
    moveElement: (node, next) ->
      parent.insertBefore(node, next)
    removeElement: (node) ->
      $node = $(node)
      # We need to compute these before the fadeOut, or the height will be incorrect
      # Moreover, it is logically correct to compare the position of the node before any scrolling
      # to the position of the viewport after any scrolling that happens during the fade (right?)
      nodeTop = node.offsetTop
      # The space we need to adjust - including top and bottom margins, if applicable
      nodeHeight = $node.outerHeight(true)

      # Fade out the node, and when completed remove it and adjust the scroll height
      $node.fadeOut "slow", ->
        $(this).remove() # equiv to parent.removeChild(node) or $node.remove()
        # Adjust scroll position around the removed element, if it was above the viewport
        if (nodeTop + nodeHeight/2) < (parent.scrollTop + $parent.height()/2)
          parent.scrollTop = parent.scrollTop - nodeHeight
      return

dragProps =
  # Adding classes is okay because we activate on mouseover
  # addClasses: false
  # containment: "window"
  cursorAt: { top: 0, left: 0 }
  distance: 5
  # Temporarily disabled, see below
  # handle: ".label" # the header
  helper: Mapper.tweetDragHelper
  revert: "invalid"
  scroll: false
  # Make it really obvious where to drop these
  start: Mapper.highlightEvents
  drag: Mapper.tweetDragScroll
  stop: Mapper.unhighlightEvents
  zIndex: 1000

Template.dataList.events =
  "click .data-cell": (e, t) -> Mapper.selectData(@_id)
  "click .action-data-hide": (e) -> Meteor.call "dataHide", @_id
  # Enable draggable when entering a tweet cell
  "mouseenter .data-cell:not(.ui-draggable-dragging)": (e) ->
    cell = $(e.target)

    # TODO remove temporary fix for jquery UI 1.11.0
    # http://bugs.jqueryui.com/ticket/10212
    cell.draggable(
      $.extend({
        handle: cell.find(".label")
      }, dragProps)
    )

    # TODO sometimes this throws an error. Why?
    cell.one("mouseleave", -> cell.draggable("destroy") )
