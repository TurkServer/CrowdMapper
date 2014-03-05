# The map needs to load first or openlayers complains
@Mapper = @Mapper || {}

@ChatUsers = new Meteor.Collection("chatusers")

Mapper.events = new EventEmitter()

Mapper.switchTab = (page) ->
  return unless page is "docs" or page is "events" or page is "map"

  return if Deps.nonreactive(-> Session.get("taskView")) is page

  $("a[data-target='#{page}']").trigger("click")
  # TODO why is this necessary? Should not be since the above should trigger it.
  Session.set("taskView", page)

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

