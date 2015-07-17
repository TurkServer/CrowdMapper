urlRe = /^(http|https):\/\/(([a-zA-Z0-9$\-_.+!*'(),;:&=]|%[0-9a-fA-F]{2})+@)?(((25[0-5]|2[0-4][0-9]|[0-1][0-9][0-9]|[1-9][0-9]|[0-9])(\.(25[0-5]|2[0-4][0-9]|[0-1][0-9][0-9]|[1-9][0-9]|[0-9])){3})|localhost|([a-zA-Z0-9\-\u00C0-\u017F]+\.)+([a-zA-Z]{2,}))(:[0-9]+)?(\/(([a-zA-Z0-9$\-_.+!*'(),;:@&=]|%[0-9a-fA-F]{2})*(\/([a-zA-Z0-9$\-_.+!*'(),;:@&=]|%[0-9a-fA-F]{2})*)*)?(\?([a-zA-Z0-9$\-_.+!*'(),;:@&=\/?]|%[0-9a-fA-F]{2})*)?(\#([a-zA-Z0-9$\-_.+!*'(),;:@&=\/?]|%[0-9a-fA-F]{2})*)?)?$/

Template.datastream.helpers
  loaded: -> Session.equals("dataSubReady", true)

Template.datastream.events
  "submit .datastream-input": (e, t) ->
    input = t.$("input[type=text]")
    url = input.val().trim()
    # Ignore empty URL
    return unless url

    # Process from http://embed.ly/static/scripts/generator.js

    # Prepend protocol if missing
    if !(/^https?:\/\//i).test(url)
      url = 'http://' + url

    if ( !urlRe.test(url) )
      bootbox.alert("Sorry! The URL <kbd>#{url}</kbd> seems to be invalid. Please fix it and try again.")
      return

    Meteor.call("dataInsert", url)

    # Success; clear input
    input.val('')

# We want events to exist and events.length > 0 to display
# So we get all docs where events either doesn't exist or it's of size 0
dataSelector = {
  $or: [
    { events: {$exists: false} },
    { events: {$size: 0} }
  ]
}

Template.dataList.helpers
  data: ->
    selector = if TurkServer.isAdmin() and Session.equals("adminShowDeleted", true)
      # Ignoring just tagged events values
      dataSelector
    else
      _.extend({}, dataSelector, { hidden: {$exists: false} })
    return Datastream.find(selector, sort: {num: 1}) # Sort in increasing insertion order

Template.dataList.rendered = ->
  AnimatedEach.attachHooks(@firstNode)

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

Template.dataList.events
  "click .data-cell": (e, t) -> Mapper.selectData(@_id)

  # Debounce multi-click data hides
  "click .action-data-hide": _.debounce( (e) ->
    # Somehow it's still possible to click hide on missing stuff. Slow machines?
    unless @_id?
      bootbox.alert("Couldn't hide that data. If this persists, try reloading the app.")
      return
    Meteor.call "dataHide", @_id
  , 750, true)

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
