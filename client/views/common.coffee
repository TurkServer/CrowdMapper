
Template.tweetIcon.rendered = ->
  $(@firstNode).popover
    html: true
    placement: "top"
    trigger: "hover"
    container: @firstNode # Hovering over the popover should hold it open
    content: =>
      # No need for reactivity (Meteor.render) here since tweet does not change
      Template.tweetPopup Datastream.findOne(@data)

Template.tweetIcon.events =
  "click .action-unlink-tweet": (e) ->
    tweetId = Spark.getDataContext(e.target)

    # TODO Fix this horrible hack for finding the event context
#    eventContext = Spark.getDataContext(e.target.parentNode.parentNode.parentNode.parentNode)

    # This is a slightly more robust hack but with worse performance
    target = e.target
    eventContext = tweetId
    while eventContext is tweetId
      eventContext = Spark.getDataContext(target = target.parentNode)

    Events.update eventContext._id,
      $pull: { sources: tweetId }

epsg4326 = null
epsg900913 = null

# Initialize these after page (OpenLayers library) loaded
Meteor.startup ->
  # TODO don't depend on this path to be accessible, serve it ourself
  OpenLayers.ImgPath = "http://dev.openlayers.org/releases/OpenLayers-2.13/img/";

  epsg4326 = new OpenLayers.Projection("EPSG:4326")
  epsg900913 = new OpenLayers.Projection("EPSG:900913")

Handlebars.registerHelper "formatLocation", ->
  point = new OpenLayers.Geometry.Point(@location[0], @location[1])
  point.transform(epsg900913, epsg4326)
  point.x.toFixed(2) + ", " + point.y.toFixed(2)
