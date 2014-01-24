Meteor.startup ->
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
      OpenLayers.Control.prototype.initialize.apply(@, arguments)
      @handler = new OpenLayers.Handler.Click(@, {'click': @trigger}, @handlerOptions)
      return # This is super important or it breaks
