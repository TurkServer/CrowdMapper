@Mapper = @Mapper || {}

# OpenLayers config - set this externally at some point
extent = [11700000, 525000, 15700000, 2450000] # Philippines

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
  # Don't re-render map due to reactive sub-regions triggering this
  return if @map

  console.log "starting map render"

#  mapLayer = new OpenLayers.Layer.OSM("Simple OSM Map");
  mapLayer = new OpenLayers.Layer.Bing
    name: "Bing Map"
    type: "Road" # "AerialWithLabels"
    key: "AtsCXPry0QFxHVXRBJDXPVVy88GhE6tTwtW61SNJoVl8AYwcNce_UsO3VZ3lGT3Q"

  vectorLayer = new OpenLayers.Layer.Vector "Vector Layer",
    styleMap: @styleMap

  map = new OpenLayers.Map 'map',
    # center: new OpenLayers.LonLat(0, 0)
    layers: [mapLayer, vectorLayer]
    maxExtent: extent
    restrictedExtent: extent
    resolutions: resolutions
    serverResolutions: serverResolutions
    theme: null # don't attempt to load theme from default path
    controls: [
      new OpenLayers.Control.Navigation(),
      new OpenLayers.Control.PanZoomBar()
    ]

  @map = map

  map.addControl new OpenLayers.Control.MousePosition
    numDigits: 2
    displayProjection: new OpenLayers.Projection("EPSG:4326")

  map.addControl(new OpenLayers.Control.LayerSwitcher({'ascending':false}));
  map.addControl(new OpenLayers.Control.OverviewMap
    mapOptions:
      theme: null # again, don't load theme
  )
  map.addControl(new OpenLayers.Control.KeyboardDefaults());

  popup = null
  selectedFeature = null

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
    else
      popup.lonlat = lonlat
      # Clear contents: see http://stackoverflow.com/questions/3955229/remove-all-child-elements-of-a-dom-node-in-javascript
      while popup.contentDiv.firstChild
        popup.contentDiv.removeChild popup.contentDiv.firstChild

    # Make that shit reactive
    # XXX Don't try to optimize this because it gets un-reactive when taken off the page anyway
    popup.contentDiv.appendChild Meteor.render ->
      new Handlebars.SafeString Template.mapPopup Events.findOne(feature.id)

    map.addPopup(popup, true) # Kick out any old popups for good measure

    # Resize popup to fit contents
    # Of course, this won't affect reactive updates but those are unlikely to trigger huge size changes
    popup.updateSize()

  hidePopup = ->
    map.removePopup(popup) if popup

  # Allow hovering over stuff
  hoverControl = new OpenLayers.Control.SelectFeature vectorLayer,
    hover: true
    highlightOnly: true
    renderIntent: "hover"
    eventListeners:
#      beforefeaturehighlighted: (e) -> console.log e
      featurehighlighted: (e) ->
        return if selectedFeature
        displayPopup(e.feature)
      featureunhighlighted: ->
        return if selectedFeature
        hidePopup()

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
      Events.update { _id: feature.id },
        $set: { location: [point.x, point.y] }

      displayPopup(selectedFeature || feature)

  vectorLayer.events.on
    "featureselected": (e) ->
      displayPopup(e.feature)
      selectedFeature = e.feature
    "featureunselected": ->
      selectedFeature = null
      hidePopup()

  # Register external helpers
  Mapper.selectEvent = (id) ->
    feature = vectorLayer.getFeatureById(id)
    return unless feature
    selectControl.unselectAll()
    map.zoomToMaxExtent()
    selectControl.select(feature)

  # Order of hover and select control matters
  map.addControl(hoverControl)
  hoverControl.activate()

  map.addControl(dragControl)
  dragControl.activate()

  map.addControl(selectControl)
  selectControl.activate()

  map.zoomToMaxExtent()

  # Get all markers
  markers = Events.find
    location: {$exists: true}

  # Observe for changes to markers (first run draws initial)
  @query = markers.observeChanges
    added: (id, fields) ->
      point = new OpenLayers.Geometry.Point(fields.location[0], fields.location[1])
      feature = new OpenLayers.Feature.Vector(point)
      feature.id = id
      vectorLayer.addFeatures([feature])

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
      hidePopup() if selectedFeature is feature
      vectorLayer.destroyFeatures [feature]

Template.map.destroyed = ->
  # Tear down observe query
  @query?.stop()

# TODO this is just a workaround but don't hardcode fields in future
Template.mapPopup.dereference = (key, value) ->
  Mapper.sources[key][value]?.text || ""
