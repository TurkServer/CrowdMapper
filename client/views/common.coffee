urlExp = /(\b(https?|ftp|file):\/\/[-A-Z0-9+&@#\/%?=~_|!:,.;]*[-A-Z0-9+&@#\/%=~_|])/ig

UI.registerHelper "replaceURLs", (text) ->
  # Shim so old links aren't broken, can be removed later for speed
  return text if text.indexOf("target='_blank'>") > -1
  text.replace(urlExp, "<a href='$1' target='_blank'>$1</a>")

Template.userList.helpers
  loaded: -> Session.equals("userSubReady", true)
  users: -> Meteor.users.find()

Template.userPill.helpers
  labelClass: ->
    if @_id is Meteor.userId()
      "inverse"
    else if @status?.online
      "success"
    else "default"

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

    user = Blaze.getData(e.target)

    if ChatUsers.findOne(userId: user._id)?
      bootbox.alert("You and #{user.username} are already in the same room.")
      return

    bootbox.confirm "Invite #{user.username} to join you in <b>" + ChatRooms.findOne(myRoom).name + "</b>?"
    , (result) ->
      Meteor.call "inviteChat", user._id, myRoom if result

# String conversion needed: https://github.com/meteor/meteor/issues/1447
Handlebars.registerHelper "findTweet", -> Datastream.findOne(""+@)

Handlebars.registerHelper "lookupUser", -> Meteor.users.findOne(""+@)

embedly 'card', {
  chrome: 0
}
# Resize embedly cards to be not so huge after render
# This seems to control the iframe before responsive sizing
embedly 'on', 'card.rendered', (iframe) ->
  # TODO destroy the shitty embedly API
  $(iframe).height(160)

###
  XXX tweet icon mouseover and dragging is handled at the global page level and the
  event page level respectively
###

Template.tweetIcon.events =
  "click .action-unlink-tweet": (e) ->
    # This needs to work on both events and map
    # both the table row and the popup are .event-record
    tweet = Blaze.getData(e.target)
    event = Blaze.getData $(e.target).closest(".event-record")[0]

    # The unlink function will also hide this if it's not tagged somewhere
    # TODO: the unlink-hide process causes an unwanted scroll adjustment
    Meteor.call "dataUnlink", tweet._id, event._id

# Mapping helpers
epsg4326 = new OpenLayers.Projection("EPSG:4326")
epsg900913 = new OpenLayers.Projection("EPSG:900913")

transformLocation = (location) ->
  point = new OpenLayers.Geometry.Point(location[0], location[1])
  point.transform(epsg900913, epsg4326)
  return [point.x, point.y]

formatLocation = (location) ->
  return "" unless location
  [x, y] = transformLocation(location)
  return x.toFixed(2) + ", " + y.toFixed(2)

Handlebars.registerHelper "formatLocation", -> formatLocation(@location)

transformLongLat = (longlat) ->
  point = new OpenLayers.Geometry.Point(longlat[0], longlat[1])
  point.transform(epsg4326, epsg900913)
  return [point.x, point.y]

minLongLat = transformLocation([Mapper.extent[0], Mapper.extent[1]])
maxLongLat = transformLocation([Mapper.extent[2], Mapper.extent[3]])

entryPrecision = 3

Template.longLatEntry.helpers
  minLong: minLongLat[0].toFixed(entryPrecision)
  maxLong: maxLongLat[0].toFixed(entryPrecision)
  minLat: minLongLat[1].toFixed(entryPrecision)
  maxLat: maxLongLat[1].toFixed(entryPrecision)

# LongLat editable
# see http://vitalets.github.io/x-editable/assets/x-editable/inputs-ext/address/address.js

LongLat = (options) ->
  @init("longlat", options, LongLat.defaults)
  return

# inherit from Abstract input
$.fn.editableutils.inherit(LongLat, $.fn.editabletypes.abstractinput)
$.extend LongLat.prototype, {

  ###
    Renders input from tpl

    @method render()
  ###
  render: ->
    @$input = @$tpl.find("input")
    return

  ###
    Default method to show value in element. Can be overwritten by display option.

    @method value2html(value, element)
  ###
  value2html: (value, element) ->
    unless value
      $(element).empty()
      return
    # Call above function to render
    $(element).html formatLocation(value)
    return

  ###
    Gets value from element's html
    We set value directly via javascript.

    @method html2value(html)
  ###
  html2value: (html) -> null

  ###
    Converts value to string.
    It is used in internal comparing (not for sending to server).

    @method value2str(value)
  ###
  value2str: formatLocation # This will ignore manual changes to the third decimal place.

  ###
    Converts string to value. Used for reading value from 'data-value' attribute.

    this is mainly for parsing value defined in data-value attribute.
    If you will always set value by javascript, no need to overwrite it

    @method str2value(str)
  ###
  str2value: (str) -> str

  ###
  Sets value of input.

  @method value2input(value)
  @param {mixed} value
  ###
  value2input: (value) ->
    return unless value
    transformed = transformLocation(value)
    @$input.filter('[name="long"]').val transformed[0].toFixed(entryPrecision)
    @$input.filter('[name="lat"]').val transformed[1].toFixed(entryPrecision)
    return

  ###
  Returns value of input.

  @method input2value()
  ###
  input2value: ->
    transformLongLat [
      @$input.filter('[name="long"]').val(),
      @$input.filter('[name="lat"]').val()
    ]

  ###
  Activates input: sets focus on the first field.

  @method activate()
  ###
  activate: ->
    @$input.filter('[name="long"]').focus()
    return

  ###
  Attaches handler to submit form in case of 'showbuttons=false' mode

  @method autosubmit()
  ###
  autosubmit: ->
    @$input.keydown (e) ->
      $(this).closest("form").submit() if e.which is 13
      return
    return
}

LongLat.defaults = $.extend {}, $.fn.editabletypes.abstractinput.defaults,
  tpl: Blaze.toHTML Template.longLatEntry # No reactive contents
  inputclass: ""

$.fn.editabletypes.longlat = LongLat
