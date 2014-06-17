###
  Subscriptions
###

fieldSub = Meteor.subscribe("eventFieldData", Mapper.processSources)

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

Meteor.subscribe("notifications") # User specific

###
  Routing
###

Router.configure
  notFoundTemplate: 'home'
  loadingTemplate: 'spinner'

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
  @route 'exitsurvey/tutorial',
    template: "tutorialSurvey"
    layoutTemplate: 'defaultContainer'
    onBeforeAction: (pause) ->
      unless TurkServer.inExitSurvey()
        @render("loadError")
        pause()
  @route 'exitsurvey/posttask',
    template: "postTaskSurvey"
    layoutTemplate: 'defaultContainer'
    # TODO deny if not in survey

Meteor.startup ->
  Session.setDefault("taskView", 'events')

  # Defer setting up these autorun functions:
  # https://github.com/EventedMind/iron-router/issues/639
  Meteor.defer ->
    Deps.autorun ->
      Router.go("/mapper") if TurkServer.inExperiment()

    # TODO generalize this based on batch
    Deps.autorun ->
      Router.go("/exitsurvey/posttask") if TurkServer.inExitSurvey()

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
    sizeWarningDialog = bootbox.dialog
      closeButton: false
      message: "<h3>Your screen is not big enough for this task. Please maximize your window if possible, or use a computer with a higher-resolution screen.</h3>"
    return

Meteor.startup ->
  checkSize()
  $(window).resize checkSize
  # Ask for username once user logs in
  TurkServer.ensureUsername()

###
  Idle Monitoring
###
Deps.autorun ->
  return unless (treatment = TurkServer.treatment())?

  # Change monitoring setting whenever treatment changes
  # The TurkServer code will automatically handle starting and stopping during an experiment
  if treatment?.tutorialEnabled
    # Mostly for testing purposes during tutorial
    TurkServer.enableIdleMonitor(30000, true)
  else
    # 8 minute idle timer, ignore window blur
    TurkServer.enableIdleMonitor(8 * 60 * 1000, false)

  return

###
  Templates and helpers
###

Template.home.landingTemplate = ->
  # TODO make this dynamic based on batch
  Template.taskLanding

Template.mapper.rendered = ->
  # Set initial active tab when state changes
  @comp = Deps.autorun ->
    tab = Session.get('taskView')
    return unless tab?
    $('.stack .pages').removeClass('active')
    $('#mapper-'+tab).addClass('active')

Template.mapper.destroyed = -> @comp.stop()

Template.guidance.message = -> Session.get("guidanceMessage")
Template.guidance.showStyle = -> if Session.get("guidanceMessage") then "" else "display: none"

switchTab = (page) ->
  return if Deps.nonreactive(-> Session.equals("taskView", page))
  Session.set("taskView", page)

Template.pageNav.events =
  "click a": (e) -> e.preventDefault()
  # This function sets the styling on the navbar as well
  "click a[data-toggle='tab']": (e) ->
    if (target = $(e.target).data("target"))?
      switchTab(target)
    else
      e.stopPropagation() # Avoid effect of click if no tab change

Template.pageNav.payment = ->
  return null unless (treatment = TurkServer.treatment())?
  return switch
    when treatment.payment? then Template.fixedPayment
    when treatment.wage?  then Template.scaledPayment
    else null

Template.pageNav.treatment = TurkServer.treatment

Template.fixedPayment.amount = -> "$" + @payment.toFixed(2)

Template.scaledPayment.amount = ->
  hours = TurkServer.Timers.activeTime() / (3600000) # millis per hour
  lowest = (@wage * hours).toFixed(2)
  highest = ((@wage + @bonus) * hours).toFixed(2)
  return "$#{lowest} - $#{highest}"

Template.scaledPayment.lowest = -> @wage.toFixed(2)
Template.scaledPayment.highest = -> (@wage + @bonus).toFixed(2)

