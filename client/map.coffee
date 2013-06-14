

# Initialize map
Template.map.rendered = ->
  OpenLayers.ImgPath = "http://dev.openlayers.org/releases/OpenLayers-2.12/img/";

  console.log "map render"

  map = new OpenLayers.Map 'map',
    center: new OpenLayers.LonLat(0, 0)
    theme: false # don't attempt to load theme from default path

  osmLayer = new OpenLayers.Layer.OSM("Simple OSM Map");

  vectorLayer = new OpenLayers.Layer.Vector("Vector Layer");
  cursorLayer = new OpenLayers.Layer.Vector("Cursor Layer");

  map.addLayers([osmLayer, vectorLayer, cursorLayer]);

  map.addControl(new OpenLayers.Control.MousePosition());
  map.addControl(new OpenLayers.Control.PanZoomBar());
  map.addControl(new OpenLayers.Control.LayerSwitcher({'ascending':false}));

  map.addControl(new OpenLayers.Control.OverviewMap(theme: false));

  map.addControl(new OpenLayers.Control.KeyboardDefaults());

  map.zoomToMaxExtent()
