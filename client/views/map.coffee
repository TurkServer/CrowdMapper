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

  OpenLayers.ImgPath = "http://dev.openlayers.org/releases/OpenLayers-2.13/img/";

  # Move popup behind vector layers - see http://www.mail-archive.com/users@openlayers.org/msg00541.html
  # OpenLayers.Map.prototype.Z_INDEX_BASE.Popup = 500

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
    type: "AerialWithLabels"
    key: "AoMrUbEFitx5QLbLsi2NNplTe84_MyCMWM1aUDkWuWPwMXU3HIwUbzOQaDWyS5a-"

  vectorLayer = new OpenLayers.Layer.Vector "Vector Layer",
    styleMap: @styleMap

  cursorLayer = new OpenLayers.Layer.Vector("Cursor Layer") # currently unused

  map = new OpenLayers.Map 'map',
    # center: new OpenLayers.LonLat(0, 0)
    layers: [mapLayer, vectorLayer, cursorLayer]
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

  map.addControl(new OpenLayers.Control.OverviewMap(theme: null));

  map.addControl(new OpenLayers.Control.KeyboardDefaults());

  # Allow hovering over stuff
  hoverControl = new OpenLayers.Control.SelectFeature vectorLayer,
    hover: true
    highlightOnly: true
    renderIntent: "hover"
#    eventListeners:
#      beforefeaturehighlighted: (e) -> console.log e
#      featurehighlighted: (e) ->
#      featureunhighlighted: (e) ->

  # Select control that manually triggers updates
  selectControl = new OpenLayers.Control.SelectFeature vectorLayer,
    clickout: false
    toggle: true

  # Allow repositioning stuff
  modifyControl = new OpenLayers.Control.ModifyFeature vectorLayer,
    standalone: true

  # Hook up layer events
  vectorLayer.events.on
    featureselected: (e) ->
      feature = e.feature
      modifyControl.selectFeature(feature)
      console.log "selected ", e.feature

      lonlat = new OpenLayers.LonLat(feature.geometry.x, feature.geometry.y)

      # TODO render popups dynamically and with fields
      content =

      unless @popup
        @popup = new OpenLayers.Popup.Anchored("event",
          lonlat,
          null, # Popup size - defaults to 200x200 or use autoSize
          null, # The HTML
          { # The anchor
            size: new OpenLayers.Size(0, 0)
            offset: new OpenLayers.Pixel(0, -36)
          }
        )
        @popup.autoSize = true # Prob won't work without specifying HTML
        @popup.relativePosition = "tr"
      else
        @popup.lonlat = lonlat
        @popup.contentDiv.innerHTML = ''

      # Make that shit reactive
      @popup.contentDiv.appendChild Meteor.render ->
        new Handlebars.SafeString Template.mapPopup Events.findOne(feature.id)

      map.addPopup(@popup, true) # Kick out any old popups for good measure

      # Resize popup to fit contents
      # Of course, this won't affect reactive updates but those are unlikely to trigger huge size changes
      @popup.updateSize()

    featureunselected: (e) ->
      modifyControl.unselectFeature(e.feature)
      console.log "unselected ", e.feature

      map.removePopup(@popup) if @popup

    featuremodified: (e) ->
      point = e.feature.geometry
      Events.update { _id: e.feature.id },
        $set:
          location: [point.x, point.y]

  # Order of hover and select control matters
  map.addControl(hoverControl)
  hoverControl.activate()

  map.addControl(selectControl)
  selectControl.activate()

  map.addControl(modifyControl)
  modifyControl.activate()

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
      vectorLayer.destroyFeatures [feature]

  # HACK: remove the explicit visibility attribute on the vector layer - causes display issues in Firefox
  Meteor.setTimeout ->
    $("g[id^=OpenLayers_Layer_Vector_]").css("visibility", '')
  , 1000

Template.map.destroyed = ->
  # Tear down observe query
  @query?.stop()
