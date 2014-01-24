# The map needs to load first or openlayers complains
@Mapper = @Mapper || {}

Mapper.events = new EventEmitter()

Mapper.switchTab = (page) ->
  return unless page is "docs" or page is "events" or page is "map"

  return if Deps.nonreactive(-> Session.get("taskView")) is page

  $("a[data-target='#{page}']").trigger("click")
  # TODO why is this necessary? Should not be since the above should trigger it.
  Session.set("taskView", page)

Mapper.highlightEvents = -> $("#events").addClass("highlighted")
Mapper.unhighlightEvents = -> $("#events").removeClass("highlighted")
