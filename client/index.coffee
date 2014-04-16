
###
  Subscriptions
###

fieldSub = Meteor.subscribe("eventFieldData")

Deps.autorun (c) ->
  return unless fieldSub.ready()
  Mapper.processSources()
  c.stop()

# Unsets and sets a session variable for a subscription
watchReady = (key) ->
  Session.set(key, false)
  return (-> Session.set(key, true))

Deps.autorun ->
  group = TurkServer.group()

  # Don't keep a room when going from tutorial to actual task
  unless group
    Session.set("room", undefined)
    return # Otherwise admin will derpily subscribe to the entire set of users

  # No need to clean up subscriptions because this is a Deps.autorun
  # We need to pass the group handle down to make Meteor think the subscription is different
  Meteor.subscribe("userStatus", group, watchReady("userSubReady"))
  Meteor.subscribe("chatrooms", group, watchReady("chatSubReady")) # Chat messages are subscribed to by room
  Meteor.subscribe("datastream", group, watchReady("dataSubReady"))
  Meteor.subscribe("docs", group, watchReady("docSubReady"))
  Meteor.subscribe("events", group, watchReady("eventSubReady"))

Meteor.subscribe("notifications")

###
  Routing
###

Router.configure
  notFoundTemplate: 'home'
  # loadingTemplate: 'spinner' # TODO get a spinner here

# TODO move the functionality of these before functions into TurkServer
Router.map ->
  @route('home', {path: '/'})
  @route 'mapper',
    template: 'mapperContainer'
    path: '/mapper'
    onBeforeAction: (pause) ->
      unless Meteor.user()
        @setLayout("defaultContainer")
        @render("awaitingLogin")
        pause()
      unless Meteor.user()?.admin or TurkServer.inExperiment()
        @setLayout("defaultContainer")
        @render("loadError")
        pause()
    ###
      Before hook is buggy due to https://github.com/EventedMind/iron-router/issues/336
      So we subscribe to EventFields statically right now.
    ###
    waitOn: fieldSub
    action: ->
      # TODO remove this when EventedMind/iron-router#607 is merged
      @setLayout(null)
      @render()
  @route 'exitsurvey',
    layoutTemplate: 'defaultContainer'
    onBeforeAction: (pause) ->
      unless TurkServer.inExitSurvey()
        @render("loadError")
        pause()

Deps.autorun ->
  Router.go("/mapper") if TurkServer.inExperiment()

Deps.autorun ->
  Router.go("/exitsurvey") if TurkServer.inExitSurvey()

###
  Window sizing warning
###
sizeWarningDialog = null

checkSize = ->
  bigEnough = $(window).width() > 1200 and $(window).height() > 500

  if bigEnough and sizeWarningDialog?
    sizeWarningDialog.modal("hide")
    sizeWarningDialog = null
    return

  if !bigEnough and sizeWarningDialog is null
    sizeWarningDialog = bootbox.dialog("<h3>Your screen is not big enough for this task. Please maximize your window if possible, or use a computer with a higher-resolution screen.</h3>")
    return

Meteor.startup ->
  checkSize()
  $(window).resize checkSize

Meteor.startup ->
  Session.setDefault("taskView", 'events')

  Session.set("scrollEvent", null)
  Session.set("scrollTweet", null)

###
  Templates and helpers
###

Template.mapper.rendered = ->
  # Set initial active tab when rendered
  tab = Session.get('taskView')
  return unless tab?
  $('#mapper-'+tab).addClass('active')

Template.guidance.message = -> Session.get("guidanceMessage")
Template.guidance.showStyle = -> if Session.get("guidanceMessage") then "" else "display: none"

switchTab = (page) ->
  return if Deps.nonreactive(-> Session.get("taskView")) is page
  Session.set("taskView", page)

Template.pageNav.events =
  "click a": (e) -> e.preventDefault()
  # These functions set the styling on the navbar as well
  "click a[data-target='docs']": -> switchTab('docs')
  "click a[data-target='events']": -> switchTab('events')
  "click a[data-target='map']": -> switchTab('map')

# Do the stack with jQuery to avoid slow reloads
Deps.autorun ->
  tab = Session.get('taskView')
  return unless tab?
  $('.stack .pages').removeClass('active')
  $('#mapper-'+tab).addClass('active')
