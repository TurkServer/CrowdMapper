Template.map.created = ->
  OpenLayers.ImgPath = "http://dev.openlayers.org/releases/OpenLayers-2.13/img/";

# Initialize map
Template.map.rendered = ->
  # Set this externally at some point
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

  console.log "map render"

#  mapLayer = new OpenLayers.Layer.OSM("Simple OSM Map");
  mapLayer = new OpenLayers.Layer.Bing
    name: "Bing Map"
    type: "AerialWithLabels"
    key: "AoMrUbEFitx5QLbLsi2NNplTe84_MyCMWM1aUDkWuWPwMXU3HIwUbzOQaDWyS5a-"

  vectorLayer = new OpenLayers.Layer.Vector "Vector Layer",
    style:
      externalGraphic: "http://dev.openlayers.org/releases/OpenLayers-2.13/img/marker.png"
      graphicWidth: 21
      graphicHeight: 25
      graphicYOffset: -24

  cursorLayer = new OpenLayers.Layer.Vector("Cursor Layer") # currently unused

  map = new OpenLayers.Map 'map',
    # center: new OpenLayers.LonLat(0, 0)
    layers: [mapLayer, vectorLayer, cursorLayer]
    maxExtent: extent
    restrictedExtent: extent
    resolutions: resolutions
    serverResolutions: serverResolutions
    theme: false # don't attempt to load theme from default path

  map.addControl(new OpenLayers.Control.MousePosition());
  map.addControl(new OpenLayers.Control.PanZoomBar());
  map.addControl(new OpenLayers.Control.LayerSwitcher({'ascending':false}));

  map.addControl(new OpenLayers.Control.OverviewMap(theme: false));

  map.addControl(new OpenLayers.Control.KeyboardDefaults());

  # Allow repositioning stuff
  modifyControl = new OpenLayers.Control.ModifyFeature vectorLayer,
    onModification: (feature) ->
      point = feature.geometry
      Events.update { _id: feature.id },
        $set:
          location: [point.x, point.y]

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
