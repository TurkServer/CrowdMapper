Meteor.startup ->
  # Serve the path that we added in the openlayers package
  OpenLayers.ImgPath = "/packages/openlayers/openlayers/img/"

  # adapted from dev.openlayers.org/releases/OpenLayers-2.13.1/examples/click.html
  OpenLayers.Control.Click = OpenLayers.Class OpenLayers.Control,
    defaultHandlerOptions: {
      'single': true
      'double': false
      'pixelTolerance': 0
      'stopSingle': false
      'stopDouble': false
    }
    initialize: (options) ->
      @handlerOptions = OpenLayers.Util.extend({}, @defaultHandlerOptions)
      OpenLayers.Control::initialize.apply(@, arguments)
      @handler = new OpenLayers.Handler.Click(@, {'click': @trigger}, @handlerOptions)
      return # This is super important or it breaks
    # Give this an explicit name so we can use its active class: .olControlClickActive
    CLASS_NAME: "OpenLayers.Control.Click"
