# The map needs to load first or openlayers complains
@Mapper = @Mapper || {}

@ChatUsers = new Mongo.Collection("chatusers")

# Allow bing map code to be loaded by OpenLayers
UI._allowJavascriptUrls()

Mapper.events = new EventEmitter()

Mapper.displayModal = (template, data, options) ->
  # minimum options to get message to show
  options ?= { message: " " }
  dialog = bootbox.dialog(options)
  # Take out the thing that bootbox rendered
  dialog.find(".bootbox-body").remove()

  # Since bootbox/bootstrap uses jQuery, this should clean up itself
  Blaze.renderWithData(template, data, dialog.find(".modal-body")[0])
  return dialog

Mapper.switchTab = (page) ->
  return unless page is "docs" or page is "events" or page is "map"
  # Simulate click on navbar in index.coffee
  $("a[data-target='#{page}']").trigger("click")
  return

scrollPos = (element, parent) ->
  scrollTop:
    parent.scrollTop() + element.position().top - parent.height() / 2 + element.height() / 2

Mapper.selectData = (id) ->
  $(".data-cell").removeClass("selected")
  $("#data-#{id}").addClass("selected") if id?
  return

Mapper.scrollToData = (id, speed = "slow") ->
  parent = $(".scroll-vertical.data-body")
  element = $("#data-#{id}")
  return unless element.length # Can't scroll to things that aren't in datastream
  parent.animate(scrollPos(element, parent), speed)
  return

Mapper.selectEvent = (id) ->
  Mapper.mapSelectEvent?(id)
  $(".events-body tr").removeClass("selected")
  $("#event-#{id}").addClass("selected") if id?
  return

Mapper.scrollToEvent = (id, speed = "slow") ->
  parent = $(".scroll-vertical.events-body")
  element = $("#event-#{id}")
  return unless element.length
  parent.animate(scrollPos(element, parent), speed)
  return

Mapper.tweetDragHelper = (e) ->
  # Get width of current item, if dragging from datastream
  currentWidth = Math.max $(this).width(), 200
  data = Blaze.getData(this)

  # Grab tweetId either from datastream object or event tweet array
  tweetId = data?._id || data
  helper = $ Blaze.toHTMLWithData Template.tweetDragHelper, Datastream.findOne(tweetId)

  # Make a clone of just the text of the same width
  # Append to events-body, so it can be scrolled while dragging (see below).
  return helper.appendTo(".events-body").width(currentWidth)

# jQuery UI's scrolling doesn't quite work. So we roll our own.
scrollSensitivity = 80
scrollSpeed = 25

Mapper.tweetDragScroll = (event, ui) ->
  scrollParent = $(".events-body")
  overflowOffset = scrollParent.offset()

  # Don't scroll if outside the x-bounds of the event window
  return unless overflowOffset.left < event.pageX < overflowOffset.left + scrollParent[0].offsetWidth

  # Adapted from https://github.com/jquery/jquery-ui/blob/1.11.0/ui/draggable.js
  if ((overflowOffset.top + scrollParent[0].offsetHeight) - event.pageY < scrollSensitivity)
    scrollParent[0].scrollTop = scrollParent[0].scrollTop + scrollSpeed;
  else if (event.pageY - overflowOffset.top < scrollSensitivity)
    scrollParent[0].scrollTop = scrollParent[0].scrollTop - scrollSpeed;

Mapper.highlightEvents = ->
  Mapper.switchTab("events")
  $("#events").addClass("highlighted")
  Session.set("guidanceMessage", "Drop on an event below to attach this tweet.")

Mapper.unhighlightEvents = ->
  $("#events").removeClass("highlighted")
  Session.set("guidanceMessage", undefined)

# Highlighting and unhighlighting map can run automatically from a placing event
Deps.autorun ->
  id = Session.get("placingEvent")
  if id
    $("#map").addClass("highlighted")
    Session.set("guidanceMessage", "Click to map a location for this event.")
  else
    $("#map").removeClass("highlighted")
    Session.set("guidanceMessage", undefined)

Mapper.extent = Meteor.settings.public.map.extent

