# The map needs to load first or openlayers complains
@Mapper = @Mapper || {}

@ChatUsers = new Meteor.Collection("chatusers")

Mapper.events = new EventEmitter()

Mapper.switchTab = (page) ->
  return unless page is "docs" or page is "events" or page is "map"
  # Simulate click on navbar in index.coffee
  $("a[data-target='#{page}']").trigger("click")
  return

scrollPos = (element, parent) ->
  scrollTop:
    parent.scrollTop() + element.position().top - parent.height()/2 + element.height()/2

Mapper.selectData = (id) ->
  $(".data-cell").removeClass("selected")
  $("#data-#{id}").addClass("selected") if id?
  return

Mapper.scrollToData = (id) ->
  parent = $(".scroll-vertical.data-body")
  element = $("#data-#{id}")
  return unless element.length # Can't scroll to things that aren't in datastream
  parent.animate(scrollPos(element, parent), "slow")
  return

Mapper.selectEvent = (id) ->
  Mapper.mapSelectEvent?(id)
  $(".events-body tr").removeClass("selected")
  $("#event-#{id}").addClass("selected") if id?
  return

Mapper.scrollToEvent = (id) ->
  parent = $(".scroll-vertical.events-body")
  element = $("#event-#{id}")
  return unless element.length
  parent.animate(scrollPos(element, parent), "slow")
  return

Mapper.highlightEvents = ->
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

