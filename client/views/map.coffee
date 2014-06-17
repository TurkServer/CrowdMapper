@Mapper = @Mapper || {}

bingAPIKey = Meteor.settings.public.map.bingAPIKey

resolutions = [19567.87923828125, 9783.939619140625,
               4891.9698095703125, 2445.9849047851562, 1222.9924523925781,
               611.4962261962891, 305.74811309814453, 152.87405654907226,
               76.43702827453613, 38.218514137268066, 19.109257068634033,
               9.554628534317017, 4.777314267158508, 2.388657133579254,
               1.194328566789627, 0.5971642833948135, 0.29858214169740677,
               0.14929107084870338, 0.07464553542435169]
serverResolutions = [156543.03390625, 78271.516953125,
                     39135.7584765625, 19567.87923828125, 9783.939619140625,
                     4891.9698095703125, 2445.9849047851562, 1222.9924523925781,
                     611.4962261962891, 305.74811309814453, 152.87405654907226,
                     76.43702827453613, 38.218514137268066, 19.109257068634033,
                     9.554628534317017, 4.777314267158508, 2.388657133579254,
                     1.194328566789627, 0.5971642833948135, 0.29858214169740677,
                     0.14929107084870338, 0.07464553542435169]

Template.map.created = ->
  # XXX Hack the shit out of the buggy-ass OpenLayers Popup

  # Move popup behind vector layers - see http://www.mail-archive.com/users@openlayers.org/msg00541.html
  # OpenLayers.Map.prototype.Z_INDEX_BASE.Popup = 500

  # Force popup to always above only
  # See original implementation in https://github.com/openlayers/openlayers/blob/master/lib/OpenLayers/Popup/Anchored.js
  OpenLayers.Popup.Anchored.prototype.calculateRelativePosition = (px) ->
    lonlat = @map.getLonLatFromLayerPx(px)
    extent = @map.getExtent()
    quadrant = extent.determineQuadrant(lonlat);

    # flip left/right but always at top
    result = ""
    result += "t"
    result += if quadrant.charAt(1) is 'l' then 'r' else 'l'
    return result

  ###
    TODO replace earthquake-3 with ${type}
  ###
  defaultStyle =
    externalGraphic: "/images/map/earthquake-3-red.png"
    graphicOpacity: 1
    graphicWidth: 32
    graphicHeight: 37
    graphicYOffset: -36

  @styleMap = new OpenLayers.StyleMap
    'default': OpenLayers.Util.applyDefaults(defaultStyle, OpenLayers.Feature.Vector.style["default"])
    hover:
      externalGraphic: "/images/map/earthquake-3-yellow.png"
    select:
      externalGraphic: "/images/map/earthquake-3-cyan.png"

# Initialize map
Template.map.rendered = ->
  mapInst = this

  politicalMapLayer = new OpenLayers.Layer.Bing
    name: "Political Map"
    type: "Road"
    key: bingAPIKey
    # Fix for the pink tiles and cross-origin errors
    tileOptions: { crossOriginKeyword: 'anonymous'}
    # transitionEffect: null

  satelliteMapLayer = new OpenLayers.Layer.Bing
    name: "Satellite Map"
    type: "AerialWithLabels"
    key: bingAPIKey
    tileOptions: { crossOriginKeyword: 'anonymous'}

  vectorLayer = new OpenLayers.Layer.Vector "Event Markers",
    styleMap: @styleMap
    displayInLayerSwitcher: false # https://github.com/openlayers/openlayers/blob/master/lib/OpenLayers/Control/LayerSwitcher.js#L289

  map = new OpenLayers.Map 'map',
    # center: new OpenLayers.LonLat(0, 0)
    layers: [politicalMapLayer, satelliteMapLayer, vectorLayer]
    # loaded in mapper.coffee
    maxExtent: Mapper.extent
    restrictedExtent: Mapper.extent
    resolutions: resolutions
    serverResolutions: serverResolutions
    theme: null # don't attempt to load theme from default path
    controls: [
      new OpenLayers.Control.LayerSwitcher( ascending: false ),
      new OpenLayers.Control.KeyboardDefaults(),
      new OpenLayers.Control.MousePosition
        numDigits: 2
        displayProjection: new OpenLayers.Projection("EPSG:4326")
      new OpenLayers.Control.Navigation(),
      new OpenLayers.Control.OverviewMap
        mapOptions: {theme: null} # again, don't load theme
      new OpenLayers.Control.PanZoomBar(),
    ]

  popup = null
  selectedFeature = null
  Session.set("popupEvent", undefined)

  displayPopup = (feature) ->
    lonlat = new OpenLayers.LonLat(feature.geometry.x, feature.geometry.y)

    unless popup
      popup = new OpenLayers.Popup.Anchored("event",
        lonlat,
        null, # Popup size - defaults to 200x200 or use autoSize; needed for FramedCloud due to bug
        null, # The HTML
        { # The anchor
          size: new OpenLayers.Size(0, 0)
          offset: new OpenLayers.Pixel(0, -36)
        }
      )

      popup.autoSize = true # Prob won't work without specifying HTML

      # Insert the popup template into the content div
      # Future updates to the selected event will be accomplished by the session variable
      UI.insert(UI.render(Template.mapPopup), popup.contentDiv)

      mapInst.popup = popup
    else
      popup.lonlat = lonlat

    map.addPopup(popup, true) # Second argument - kick out any old popups for good measure
    # Re-render the popup
    Session.set("popupEvent", feature.id)
    # Resize popup to fit contents, after visual update
    # Resizing won't affect reactive updates but those are unlikely to trigger huge size changes
    Deps.flush()
    popup.updateSize()
    # Fix issues with size update on newly placed item, just in case
    setTimeout ->
      popup.updateSize()
    , 0

  hidePopup = ->
    Session.set("popupEvent", undefined)
    map.removePopup(popup) if popup

  placeControl = new OpenLayers.Control.Click
    trigger: (e) ->
      lonlat = map.getLonLatFromPixel(e.xy)
      id = Session.get("placingEvent")
      Session.set("placingEvent", undefined) # Also deactivates the control
      return unless id
      Meteor.call "updateEvent", id,
        location: [lonlat.lon, lonlat.lat]

  # Allow hovering over stuff
  hoverControl = new OpenLayers.Control.SelectFeature vectorLayer,
    hover: true
    highlightOnly: true
    renderIntent: "hover"
    eventListeners:
#      beforefeaturehighlighted: (e) -> console.log e
      featurehighlighted: (e) -> displayPopup(e.feature) unless selectedFeature
      featureunhighlighted: -> hidePopup() unless selectedFeature

  # Select control that manually triggers updates
  selectControl = new OpenLayers.Control.SelectFeature vectorLayer,
    clickout: true
    toggle: true

  dragControl = new OpenLayers.Control.DragFeature vectorLayer,
    # This hides ANY feature while dragging and displays the selected one or dragged one
    # XXX this is a little inefficient to do on each drag but the start carries all mouseclicks
    onDrag: hidePopup

    onComplete: (feature, pixel) ->
      point = feature.geometry
      Meteor.call "updateEvent", feature.id,
        location: [point.x, point.y]

      displayPopup(selectedFeature || feature)

  map.addControl(placeControl) # but don't activate till we need to place an event

  # Order of hover and select control matters
  map.addControl(hoverControl)
  hoverControl.activate()

  map.addControl(dragControl)
  dragControl.activate()

  map.addControl(selectControl)
  selectControl.activate()

  map.zoomToMaxExtent()

  # Observe for changes to markers (first run draws initial)
  @query = Events.find({
    deleted: {$exists: false}
    location: {$exists: true}
  }).observeChanges
    added: (id, fields) ->
      point = new OpenLayers.Geometry.Point(fields.location[0], fields.location[1])
      feature = new OpenLayers.Feature.Vector(point)
      feature.id = id
      vectorLayer.addFeatures([feature])
      # Show popup for this feature if it's selected (i.e. we just placed it)
      # TODO takes two clicks to select something after this
      if $("#event-#{id}").hasClass("selected")
        selectControl.unselectAll()
        selectControl.select(feature)

    changed: (id, fields) ->
      feature = vectorLayer.getFeatureById(id)
      # don't draw unless the feature exists and location changed
      return unless feature and fields.location

      feature.geometry.x = fields.location[0]
      feature.geometry.y = fields.location[1]

      # redraw the feature
      vectorLayer.drawFeature(feature)

    removed: (id) ->
      feature = vectorLayer.getFeatureById(id)
      return unless feature
      # Clean up a possibly displayed popup for this
      if selectedFeature is feature
        selectedFeature = null
        hidePopup()
      vectorLayer.destroyFeatures [feature]

  ###
    Vector Layer events.
    Set or unset selected feature before setting the session variable;
    It determines if we should zoom or not.
  ###
  vectorLayer.events.on
    "featureselected": (e) ->
      displayPopup(e.feature)
      selectedFeature = e.feature
      Mapper.selectEvent(selectedFeature.id)
    "featureunselected": (e) ->
      selectedFeature = null
      hidePopup()
      # Only set selected event to null if we unselected via the map
      Mapper.selectEvent(null) if $("#event-#{e.feature.id}").hasClass("selected")

  # Handle outside event selection
  Mapper.mapSelectEvent = (id) ->
    return unless id
    feature = vectorLayer.getFeatureById(id)
    return if selectedFeature is feature # Don't select/zoom if we already selected this
    selectControl.unselectAll()
    return unless feature # Unselect if the event exists but is not on map
    selectControl.select(feature)
    map.zoomToMaxExtent()

  # Watch for event placing, this sets the crosshair using CSS
  @placingComp = Deps.autorun ->
    if Session.get("placingEvent")
      placeControl.activate()
    else
      placeControl.deactivate()

Template.map.destroyed = ->
  # We need to clear any contents using jQuery
  # to ensure that their reactive (?) deps are cleaned up:
  # https://github.com/meteor/meteor/issues/2031#issuecomment-40511526
  # TODO this doesn't actually take off the reactive computation, but should only affect admin
  if @popup
    $(@popup.contentDiv).empty()
    console.log "Popup elements removed"

  # Tear down observe query
  @query?.stop()
  # Stop placing computation
  @placingComp?.stop()

Template.mapPopup.events =
  "click .action-event-unmap": ->
    Meteor.call "unmapEvent", @_id

Template.mapPopup.eventRecord = ->
  eventId = Session.get("popupEvent")
  # console.log "recomputing " + eventId
  return Events.findOne(eventId) if eventId?

Template.mapPopup.destroyed = -> console.log "map popup destroyed"

# TODO this is just a workaround but don't hardcode fields in future
Template.mapPopup.dereference = (key, value) ->
  Mapper.sources[key][value]?.text || ""
