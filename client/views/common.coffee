Template.userPill.labelClass = ->
  if @_id is Meteor.userId()
    "label-warning"
  else if @profile?.online
    "label-success"
  else ""

Template.userPill.rendered = ->
  # Show chat invite?
  if @data.profile?.online and @data._id isnt Meteor.userId()
    $(@firstNode).popover
      html: true
      placement: "bottom"
      trigger: "hover"
      container: @firstNode
      content: =>
        # Also no reactive here
        Template.userInvitePopup()

Template.userPill.events =
  "click .action-chat-invite": (e) ->
    myId = Meteor.userId()
    unless myId?
      bootbox.alert("You must be logged in to invite others to chat.")
      return

    myRoom = Session.get("room")
    unless myRoom?
      bootbox.alert("Join a chat room first to invite someone to chat with you.")
      return

    user = Spark.getDataContext(e.target)

    if ChatUsers.findOne(userId: user._id)?
      bootbox.alert("You and #{user.username} are already in the same room.")
      return

    bootbox.confirm "Invite #{user.username} to join you in <b>" + ChatRooms.findOne(myRoom).name + "</b>?"
    , (result) ->
      # TODO make this a method later
      Notifications.insert(
        user: user._id
        sender: myId
        type: "invite"
        room: myRoom
      ) if result

Handlebars.registerHelper "findTweet", ->
  # FIXME wtf is handlebars doing here?
  Datastream.findOne(this.toString())

Template.tweetIcon.rendered = ->
  $(@firstNode).popover
    html: true
    placement: "top"
    trigger: "hover"
    container: @firstNode # Hovering over the popover should hold it open
    content: =>
      # No need for reactivity (Meteor.render) here since tweet does not change
      Template.tweetPopup Datastream.findOne(@data)

  $(@firstNode).draggable
    addClasses: false
    # containment: "window"
    cursorAt: { top: 0, left: 0 }
    distance: 5
    revert: "invalid"
    scroll: false
    zIndex: 1000
    helper: ->
      # TODO: fixme don't clone the popover if there is one
      return $(this).clone().remove(".popover")

Template.tweetIcon.events =
  "click .action-unlink-tweet": (e) ->
    # This needs to work on both events and map
    tweet = Spark.getDataContext(e.target)

    # TODO Fix this horrible hack for finding the event context
#    eventContext = Spark.getDataContext(e.target.parentNode.parentNode.parentNode.parentNode)

    # This is a slightly more robust hack but with worse performance
    target = e.target
    eventContext = tweet
    while eventContext is tweet
      eventContext = Spark.getDataContext(target = target.parentNode)

    Meteor.call "dataUnlink", tweet._id, eventContext._id

    # Hide this if it's not tagged somewhere
    Meteor.call "dataHide", tweet._id

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

# TODO: fix inefficient double lookup here
Template.userLookup.doc = ->
  Meteor.users.findOne({username: this.substring(1)})

Template.tweetLookup.doc = ->
  Datastream.findOne(this.substring(1))

showEvent = (eventId) ->
  Mapper.switchTab 'events' # Make sure we are on the event page
  # Set up a scroll event, then trigger a re-render
  Session.set("selectedEvent", null)
  Session.set("scrollEvent", eventId)
  Session.set("selectedEvent", eventId)

Template.tweetLookup.events =
  "click .clickme": (e) ->
    if @hidden
      bootbox.alert("That data has been deleted.")
    else if @events and @events.length > 0
      # Scroll to event
      eventId = @events[0]
      showEvent(eventId)
    else
      # Scroll to tweet
      Session.set("selectedTweet", null)
      Session.set("scrollTweet", @_id)
      Session.set("selectedTweet", @_id)

Template.eventLookup.doc = ->
  Events.findOne({num: parseInt(this.substring(1))})

Template.eventLookup.events =
  "click .clickme": (e) -> showEvent(@_id)


