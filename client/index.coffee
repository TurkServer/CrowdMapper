###
  Subscriptions
###

fieldSub = Meteor.subscribe("eventFieldData", Mapper.processSources)

# Unsets and sets a session variable for a subscription
watchReady = (key) ->
  Session.set(key, false)
  # TODO temporary hack for people pushing back button / Meteor re-subscribe foolishness.
  # Show loading for at most 8 seconds. This is better than infinitely bugging out because most people seem to load the app just fine.
  Meteor.setTimeout((-> Session.set(key, true)), 8000)
  return (-> Session.set(key, true))

###
  Routing
###

Router.configure
  notFoundTemplate: 'home'
  loadingTemplate: 'spinner'

# TODO move the functionality of these before functions into TurkServer by providing built-in Iron Router controllers
Router.map ->
  @route('home', {path: '/'})

  @route 'mapper',
    path: '/mapper'
    onBeforeAction: ->
      unless Meteor.user()
        @layout("defaultContainer")
        @render("awaitingLogin")
      else unless TurkServer.isAdmin() or TurkServer.inExperiment()
        @layout("defaultContainer")
        @render("loadError")
      else
        @next()

    subscriptions: ->
      subHandles = [ fieldSub ]

      return subHandles

  @route 'exitsurvey/:template?',
    layoutTemplate: 'defaultContainer'
    onBeforeAction: ->
      unless TurkServer.isAdmin() or TurkServer.inExitSurvey()
        @layout("defaultContainer")
        @render("loadError")
      else
        @next()
    action: ->
      # Override the route, for debugging use.
      if @params.template?
        @render(@params.template)
      else
        @render("exitsurvey")

Meteor.startup ->
  Session.setDefault("taskView", 'events')

  # Temporary iron router workaround
  Tracker.autorun ->
    return unless TurkServer.inExperiment()

    group = TurkServer.group()
    # Don't keep a room when going from tutorial to actual task
    # TODO this can be removed when the chat subscription is fixed
    unless group
      Session.set("room", undefined)
      return # Otherwise admin will derpily subscribe to the entire set of users

    # No need to clean up subscriptions because this is a Deps.autorun
    # We need to pass the group handle down to make Meteor think the subscription is different
    Meteor.subscribe("userStatus", group, watchReady("userSubReady"))
    # Chat messages are subscribed to by room
    Meteor.subscribe("chatrooms", group, watchReady("chatSubReady"))
    Meteor.subscribe("datastream", group, watchReady("dataSubReady"))
    Meteor.subscribe("docs", group, watchReady("docSubReady"))
    Meteor.subscribe("events", group, watchReady("eventSubReady"))
    # User specific, but shouldn't leak across instances
    Meteor.subscribe("notifications", group)
    return

  # Defer setting up these autorun functions:
  # https://github.com/EventedMind/iron-router/issues/639
  Meteor.defer ->
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
    sizeWarningDialog = bootbox.dialog
      closeButton: false
      message: "<h3>Your screen is not big enough for this task. Please maximize your window if possible, or use a computer with a higher-resolution screen.</h3>"
    return

Meteor.startup ->
  checkSize()
  $(window).resize checkSize
  # Ask for username once user logs in
  Meteor.defer TurkServer.ensureUsername, 5000

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

# TODO update this to use a more generalized API
Template.home.helpers
  landingTemplate: ->
    treatments = TurkServer.batch()?.treatments
    if _.indexOf(treatments, "recruiting") >= 0
      Template.recruitingLanding
    else if _.indexOf(treatments, "parallel_worlds") >= 0
      Template.taskLanding
    else
      Template.loadingLanding

###
  Global level events in the mapper application - activating popovers on
  mouseover

  TODO generalize events below to remove boilerplate
###
popoverDelay = 200

Template.mapper.events
  # Attach and destroy a popover when mousing over a container. 'mouseenter'
  # only fires once when entering an element, so we use that to ensure that we
  # get the right target. However, exclude containers being dragged.
  "mouseenter .tweet-icon-container:not(.ui-draggable-dragging)": (e) ->
    container = $(e.target)
    tweet = Blaze.getData(e.target)
    delayShow = true

    Meteor.setTimeout ->
      # Skip creating popover if moused out already
      return unless delayShow

      container.popover({
        html: true
        placement: "auto right" # Otherwise it goes off the top of the screen
        trigger: "manual"
        container: e.target # Hovering over the popover should hold it open
        # No need for reactivity here since tweet does not change
        content: Blaze.toHTMLWithData Template.tweetPopup, Datastream.findOne(tweet._id)
      }).popover("show")
    , popoverDelay

    container.one "mouseleave", ->
      delayShow = false
      # Destroy any popover if it was created
      container.popover("destroy")

  "mouseenter .user-pill-container": (e) ->
    container = $(e.target)

    container.popover({
      html: true
      placement: "auto right"
      trigger: "manual"
      container: e.target
      content: ->
        # Grab updated data
        user = Blaze.getData(e.target)
        # Check if we should show chat invite
        if user.status?.online and user._id isnt Meteor.userId()
          return Blaze.toHTML Template.userInvitePopup
        else
          return null
    }).popover("show")

    container.one("mouseleave", -> container.popover("destroy") )

Template.mapper.helpers
  adminControls: Template.adminControls

Template.mapper.rendered = ->
  # Set initial active tab when state changes
  @comp = Deps.autorun ->
    tab = Session.get('taskView')
    return unless tab?
    $('.stack .pages').removeClass('active')
    $('#mapper-'+tab).addClass('active')

Template.mapper.destroyed = -> @comp?.stop()

Template.guidance.helpers
  message: -> Session.get("guidanceMessage")

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

Template.pageNav.helpers
  payment: ->
    return null unless (treatment = TurkServer.treatment())?
    return switch
      when treatment.payment? then Template.tutorialPayment
      when treatment.wage?  then Template.scaledPayment
      else null
  treatment: TurkServer.treatment

Template.tutorialPayment.helpers
  amount: -> "$" + @payment.toFixed(2)

Template.scaledPayment.helpers
  amount: ->
    hours = TurkServer.Timers.activeTime() / (3600000) # millis per hour
    lowest = (@wage * hours).toFixed(2)
    highest = ((@wage + @bonus) * hours).toFixed(2)
    return "$#{lowest} - $#{highest}"
  lowest: -> @wage.toFixed(2)
  highest: -> (@wage + @bonus).toFixed(2)

Template.help.helpers
  teamInfo: ->
    switch @groupSize
      when 1 then "You are working <b>by yourself</b>. There are no other team members for this task."
      when undefined then "You are working in a <b>team</b>."
      else "You are working in a <b>team of #{@groupSize} members</b>."

  instructionsInfo: ->
    instr = "Refer to the <b>Instructions</b> document for an overview of the instructions."
    if @groupSize > 1 or not @groupSize?
      instr += " You should feel free to ask your teammates about anything that you don't understand."
    return instr

Template.help.rendered = ->
  this.$(".dropdown > a").click()
