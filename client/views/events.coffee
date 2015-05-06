@Mapper = @Mapper || {}

# This function needs to be run before any of the event logic can happen
Mapper.processSources = ->
  # Process event choices into choice arrays
  sources = {}
  EventFields.find().forEach (field) ->
    if field.type isnt "dropdown"
      sources[field.key] = null
    else
      sources[field.key] = []
      for choice, i in field.choices
        sources[field.key].push
          text: choice
          value: i

  Mapper.sources = sources
  # Grab the fields just once ...?
  Mapper.staticFields = EventFields.find({}, {sort: {order: 1}}).fetch()

Handlebars.registerHelper "eventFields", ->
  # Process the sources if we are missing the static fields
  # Problem occured when sub ready but dependent calculation didn't run yet
  unless Mapper.staticFields
    Mapper.processSources()
  Mapper.staticFields

generateNewEvent = ->
  eventId = Random.id()

  fields = {}
  for key, val of Mapper.sources
    fields[key] = if val? then null else ""

  Meteor.call "createEvent", eventId, fields
  Mapper.selectEvent(eventId)
  return eventId

edit = (e) ->
  Meteor.call "editEvent", @_id
  Mapper.switchTab "events"
  # TODO: scrolling not working properly after new event
  Mapper.scrollToEvent(@_id)

# Set initial sort order on start
Meteor.startup ->
  Session.setDefault("eventSortKey", "num")
  Session.setDefault("eventSortOrder", 1)

Template.eventsHeader.helpers
  labelClass: ->
    key = @key || "num" # FIXME: hack for the first num field
    if Session.equals("eventSortKey", key) then "inverse" else "default"

  iconClass: ->
    key = @key || "num" # FIXME: hack for the first num field
    if Session.equals("eventSortKey", key)
      # TODO This is inefficient. Fix it.
      if Session.get("eventSortOrder") is 1
        "chevron-up"
      else
        "chevron-down"
    else
      "resize-vertical"

tweetIconDragProps =
  # addClasses: true
  # containment: "window"
  cursorAt: { top: 0, left: 0 }
  distance: 5
  # Temporary fix, see below
  # handle: ".label"
  helper: Mapper.tweetDragHelper
  revert: "invalid"
  scroll: false
  start: Mapper.highlightEvents
  drag: Mapper.tweetDragScroll
  stop: Mapper.unhighlightEvents
  zIndex: 1000

Template.eventRecords.helpers
  loaded: -> Session.equals("eventSubReady", true)

Template.eventsHeader.events
  "click span.sorter": (e) ->
    key = $(e.target).closest("span.sorter").data("key")
    sortKey = Session.get("eventSortKey")
    if sortKey? and key is sortKey
      # swap order of existing sort
      Session.set("eventSortOrder", -1 * Session.get("eventSortOrder"))
    else
      Session.set("eventSortKey", key)
      Session.set("eventSortOrder", 1)

Template.eventsBody.events
  "click tbody > tr": (e, t) ->
    Mapper.selectEvent(@_id)

  ###
    The following mouseover events are scoped to the event records table only.
  ###
  "mouseenter .tweet-icon-container": (e) ->
    container = $(e.target)

    # TODO remove temporary fix for jquery UI 1.11.0
    # http://bugs.jqueryui.com/ticket/10212
    container.draggable(
      $.extend({
        handle: container.find(".label")
      }, tweetIconDragProps)
    )

    container.one("mouseleave", -> container.draggable("destroy") )

  "mouseenter .event-voting-container": (e) ->
    container = $(e.target)

    container.popover({
      html: true
      placement: "left"
      trigger: "manual"
      container: container # Hovering over the popover should hold it open
      content: ->
        event = Blaze.getData(e.target)
        # TODO Make this properly reactive - currently just hiding it immediately after vote
        Blaze.toHTMLWithData Template.eventVotePopup, event
    }).popover('show')

    container.one("mouseleave", -> container.popover("destroy") )

Template.eventsBody.helpers
  noEvents: ->
    Events.find(deleted: {$exists: false}).count() is 0

Handlebars.registerHelper "numEventCols", ->
  # Used for rendering whole-width rows
  # Add 1 each for index, sources, map, and buttons
  EventFields.find().count() + 4

Template.eventsBody.helpers
  records: ->
    selector = if TurkServer.isAdmin() and Session.equals("adminShowDeleted", true) then {}
    else { deleted: {$exists: false} }

    key = Session.get("eventSortKey")
    # Secondary sort by key prevents jumping
    #  sort[key] = Session.get("eventSortOrder") || 1 if key?
    sort = [ [key, if Session.get("eventSortOrder") is -1 then "desc" else "asc"], [ "_id", "asc" ] ]
    return Events.find(selector, { sort: sort })

Template.eventsBody.rendered = ->
  AnimatedEach.attachHooks this.find("table tbody")

Template.createFooter.events =
  # Debounce spamming event creation
  "click .action-event-new": _.debounce( (e) ->
    e.preventDefault()
    eventId = generateNewEvent()
    # Edit and scroll to the event
    edit.call({_id: eventId})
  , 600, true)

# This function is called for *every draggable on the page* ! So minimizing
# the number of active draggables will speed things up significantly.
acceptDrop = (draggable) ->
  # Don't accept drops when looking at other pages
  return false unless Session.equals("taskView", 'events')
  event = Blaze.getData(this) # These are the only droppables on the page
  return false unless event
  tweet = Blaze.getData(draggable.context)

  # Upon a drop, data context may be lost, in which case we should not try and
  # drop check if the tweet is part of an event, below
  return false unless tweet?

  ###
    Don't accept drops to the same event. There are two ways to do this:

    - check the event as it will be more up to date than the one-shot data
    context being used to render the helper, which may have changed.

    - check the tweet to see if the event is attached.

    TODO we need to implement something that will allow for admin cleanup of
    multi-tagged events in the ground truth.
  ###
  return false if $.inArray(tweet._id, event.sources) >= 0
  return true

processDrop = (event, ui) ->
  event = Blaze.getData(this)
  return unless event

  tweet = Blaze.getData(ui.draggable.context)
  # Don't do anything if this tweet is already on this event
  return if $.inArray(tweet._id, event.sources) >= 0

  # TODO replace with an appropriate use of Template.parentData
  target = ui.draggable.context
  parent = tweet

  deletedWhileDragging = false

  while parent is tweet
    target = target.parentNode

    ###
      At this point, target will either be the datastream list
      or an event (if dragged from another event). It could also be null if the
      original draggable was removed while dragging. Possible cases:

      - Tweet hidden while dragging from the datastream
      - Tweet moved/removed or event deleted while dragging from an event
      - Event edited while dragging, causing a re-render

      TODO: handle case where event is edited so that dragging is still valid, but
      is now rejected because the context was re-rendered

      For now, we just adopt a conservative policy to prevent sync problems.
    ###
    unless target?
      deletedWhileDragging = true
      break

    parent = Blaze.getData(target)

  if deletedWhileDragging
    bootbox.alert("The tweet was hidden or the event was edited by someone else while you were dragging. Please try dragging the tweet again.")
    return

  # Distinguish between a link and a re-drag
  if parent?._id
    # remove from parent if it was an event
    Meteor.call "dataMove", tweet._id, parent._id, event._id
  else
    Meteor.call "dataLink", tweet._id, event._id

Template.eventRow.rendered = ->
  $(@firstNode).droppable
    addClasses: false
    hoverClass: "success"
    tolerance: "pointer"
    accept: acceptDrop
    drop: processDrop

Template.eventRow.events =
  "click .action-event-mapview": (e) ->
    e.preventDefault()
    # Clicking the row should already select the event
    # This automatically switches the tab view
    Mapper.switchTab "map"

  "click .action-event-locate": (e) ->
    Session.set("placingEvent", @_id)
    Mapper.switchTab("map")
    e.stopPropagation() # So the below handler can do its work

    # Cancel event placement and go back to events if clicking randomly
    $("body").one "click", ->
      if Session.get("placingEvent")
        Mapper.switchTab("events")
        Session.set("placingEvent", undefined)

  "dblclick tr": edit

# This is used in both table row and map popup
Template.editCell.helpers
  otherEditorUser: ->
    if @editor? and @editor isnt Meteor.userId()
      return Meteor.users.findOne(@editor)
    return null

Template._editCellOpen.events =
  "click .action-event-edit": edit

  "click .action-event-delete": (e) ->
    bootbox.confirm "Really delete this event? This cannot be undone!"
    , (result) =>
      Meteor.call("deleteEvent", @_id) if result

Template._editCellSelf.events =
  "click .action-event-save": (e) ->
    Meteor.call "saveEvent", @_id

###
  Rendering and helpers for individual sheet cells
###
Template.eventRow.helpers
  rowClass: ->
    if @deleted
      "deleted"
    else if @editor is Meteor.userId()
      "info"
    else if @editor
      "warning"
    else
      ""

  eventCell: ->
    if this?.type is "dropdown"
      return Template.eventCellSelect
    else
      return Template.eventCellText

# TODO instead of ad hoc building data in the future, use either Template.parentData through the UI.dynamic, or appropriate use of {{..}}
Template.eventRow.helpers
  buildData: (context, field) ->
    obj = {
      _id: context._id
      key: field.key
      name: field.name
      value: context[field.key]
      editable: context.editor is Meteor.userId()
    }

    if field?.type is "dropdown" and obj.value?
      obj.textValue = Mapper.sources[field.key][obj.value]?.text

    return obj

# Partial implementation of the code from http://stackoverflow.com/a/23144211/586086
# Except, we don't need to update the form content because we are the only one editing
# Autotext is disabled so that 'Empty' is never written and breaking reactivity

Template.eventCellTextEditable.rendered = ->
  return unless @data.editable
  @$('div.editable').editable
    display: ->
    success: (response, newValue) =>
      result = {}
      result[@data.key] = newValue
      Meteor.call "updateEvent", @data._id, result
      return true
    value: @data.value # Otherwise (empty) rendering shows up
  return

Template.eventCellSelectEditable.rendered = ->
  return unless @data.editable
  @$('div.editable').editable
    display: ->
    success: (response, newValue) =>
      result = {}
      result[@data.key] = parseInt(newValue) # Make sure we store an int back in the database
      Meteor.call "updateEvent", @data._id, result
      return true
    value: @data.value
    source: Mapper.sources[@data.key]
  return

Template.eventLocation.helpers
  editable: -> @editor is Meteor.userId()

Template.eventLocationEditable.rendered = ->
  return unless @data.editor is Meteor.userId()
  @$('div.editable').editable
    display: ->
    placement: "left" # Because this is taller than other editables
    success: (response, newValue) =>
      Meteor.call "updateEvent", @data._id, { location: newValue }
      return true
    value: @data.location
  return

# TODO fix issue with double clicking carets in location editor closing it

# We can use 'destroy' here because the popover is activated on mouseover
Template.eventVoting.events =
  "click .action-event-upvote": (e, tmpl) ->
    Meteor.call "voteEvent", @_id
    $(e.target).closest(".event-voting-container").popover('destroy')
  "click .action-event-unvote": (e, tmpl) ->
    Meteor.call "unvoteEvent", @_id
    $(e.target).closest(".event-voting-container").popover('destroy')

Template.eventVoting.helpers
  badgeClass: -> if @votes?.length > 0 then "alert-success" else ""
  numVotes: -> @votes?.length || 0

Template.eventVotePopup.helpers
  anyVotes: -> @votes?.length > 0
  iVoted: ->
    userId = Meteor.userId()
    return userId && _.contains(@votes, userId)
