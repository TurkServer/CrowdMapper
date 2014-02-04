
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
  # Remember, we need to pass the group handle down to make Meteor think the subscription is different

  # No need to clean up subscriptions on this autorun

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

Router.map ->
  @route('home', {path: '/'})
  @route 'mapper',
    template: 'mapperContainer'
    path: '/mapper'
    before: ->
      unless Meteor.user()
        @setLayout("defaultContainer")
        @render("awaitingLogin")
        @stop()
      unless Meteor.user()?.admin or TurkServer.inExperiment()
        @setLayout("defaultContainer")
        @render("loadError")
        @stop()
    ###
      Before hook is buggy due to https://github.com/EventedMind/iron-router/issues/336
      So we subscribe to EventFields statically right now.
    ###
    waitOn: fieldSub
  @route 'exitsurvey',
    layoutTemplate: 'defaultContainer'
    # TODO make sure we are allowed to be in here

Deps.autorun ->
  Router.go("/mapper") if TurkServer.inExperiment()

Deps.autorun ->
  Router.go("/exitsurvey") if TurkServer.inExitSurvey()

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

Template.pageNav.events =
  "click a": (e) -> e.preventDefault()

  "click a[data-target='docs']": ->
    Mapper.switchTab('docs')
  "click a[data-target='events']": ->
    Mapper.switchTab('events')
  "click a[data-target='map']": ->
    Mapper.switchTab('map')

# Do the stack with jQuery to avoid slow reloads
Deps.autorun ->
  tab = Session.get('taskView')
  return unless tab?
  $('.stack .pages').removeClass('active')
  $('#mapper-'+tab).addClass('active')
