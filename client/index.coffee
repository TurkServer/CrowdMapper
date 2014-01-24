
###
  Subscriptions
###

fieldSub = Meteor.subscribe("eventFieldData")

Deps.autorun ->
  return unless fieldSub.ready()
  Mapper.processSources()
  @stop()

Meteor.subscribe("chatrooms")
# Chat messages are subscribed to individually

Meteor.subscribe("userStatus")

Meteor.subscribe("datastream")
Meteor.subscribe("docs")

Meteor.subscribe("events")

Meteor.subscribe("notifications")

###
  Routing
###

Router.configure
  notFoundTemplate: 'home'
  # loadingTemplate: 'spinner' # TODO get a spinner here

Router.map ->
  @route('home', {path: '/'})
  @route 'mapper',
    template: 'mapperContainer'
    path: '/mapper/:tutorial?'
    ###
      Before hook is buggy due to https://github.com/EventedMind/iron-router/issues/336
      So we subscribe to EventFields statically right now.
    ###
    waitOn: fieldSub
    data: -> { tutorialEnabled: @params.tutorial is "tutorial" }

###
  Window sizing warning
###
sizeWarningDialog = null

checkSize = ->
  bigEnough = $(window).width() > 1250 and $(window).height() > 500

  if bigEnough and sizeWarningDialog?
    sizeWarningDialog.modal("hide")
    sizeWarningDialog = null
    return

  if !bigEnough and sizeWarningDialog is null
    sizeWarningDialog = bootbox.dialog("<h3>Your screen is not big enough for this task. Please maximize your window if possible.</h3>")
    return

Meteor.startup ->
  checkSize()
  $(window).resize checkSize
