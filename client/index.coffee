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
    onBeforeAction: (pause) ->
      unless Meteor.user()
        @setLayout("defaultContainer")
        @render("awaitingLogin")
        pause()
      unless TurkServer.isAdmin() or TurkServer.inExperiment()
        @setLayout("defaultContainer")
        @render("loadError")
        pause()

    waitOn: ->
      subHandles = [ fieldSub ]

      group = TurkServer.group()
      # Don't keep a room when going from tutorial to actual task
      # TODO this can be removed when the chat subscription is fixed
      unless group
        Session.set("room", undefined)
        return subHandles # Otherwise admin will derpily subscribe to the entire set of users

      # No need to clean up subscriptions because this is a Deps.autorun
      # We need to pass the group handle down to make Meteor think the subscription is different
      subHandles.push Meteor.subscribe("userStatus", group, watchReady("userSubReady"))
      # Chat messages are subscribed to by room
      subHandles.push Meteor.subscribe("chatrooms", group, watchReady("chatSubReady"))
      subHandles.push Meteor.subscribe("datastream", group, watchReady("dataSubReady"))
      subHandles.push Meteor.subscribe("docs", group, watchReady("docSubReady"))
      subHandles.push Meteor.subscribe("events", group, watchReady("eventSubReady"))
      # User specific, but shouldn't leak across instances
      subHandles.push Meteor.subscribe("notifications", group)

      return subHandles

  # This watching does not grab treatment data, but isn't limited to one open at a time.
  @route 'watch',
    path: '/watch/:instance'
    template: 'mapper',
    onBeforeAction: (pause) ->
      pause() unless TurkServer.isAdmin()
    waitOn: ->
      return unless @params.instance
      # Need to set all these session variables to true for it to work
      Meteor.subscribe "adminWatch", @params.instance, ->
        Session.set("userSubReady", true)
        Session.set("chatSubReady", true)
        Session.set("dataSubReady", true)
        Session.set("docSubReady", true)
        Session.set("eventSubReady", true)

  # Route to re-play a given crisis mapping instantiation
  @route 'replay',
    path: '/replay/:instance/:speed?'
    template: 'mapper',
    onBeforeAction: (pause) ->
      pause() unless TurkServer.isAdmin()

    waitOn: ->
      speed = parseFloat(this.params.speed) || 20
      Meteor.subscribe "replay", this.params.instance, speed, ->
        Session.set("userSubReady", true)
        # Session.set("chatSubReady", true)
        Session.set("dataSubReady", true)
        # Session.set("docSubReady", true)
        Session.set("eventSubReady", true)

    onAfterAction: ->
      # turn on auto scrolling for new events and hidden tweets
      @dataWatcher = Datastream.find({hidden: $exists: false}).observeChanges
        removed: (id) -> Mapper.scrollToData(id, 100)

      @eventWatcher = Events.find().observeChanges
        added: (id) ->
          Deps.afterFlush -> Mapper.scrollToEvent(id, 100)

    onStop: ->
      @dataWatcher.stop()
      @eventWatcher.stop()

  @route 'exitsurvey/:template?',
    layoutTemplate: 'defaultContainer'
    onBeforeAction: (pause) ->
      unless TurkServer.isAdmin() or TurkServer.inExitSurvey()
        @setLayout("defaultContainer")
        @render("loadError")
        pause()
    action: ->
      # Override the route, for debugging use.
      if @params.template?
        @render(@params.template)
      else
        @render("exitsurvey")

Meteor.startup ->
  Session.setDefault("taskView", 'events')

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

# TODO update this to use a more generalized API
Template.home.landingTemplate = ->
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
###
Template.mapper.events
  # Attach and destroy a popover when mousing over a container. 'mouseenter'
  # only fires once when entering an element, so we use that to ensure that we
  # get the right target. However, exclude containers being dragged.
  "mouseenter .tweet-icon-container:not(.ui-draggable-dragging)": (e) ->
    container = $(e.target)
    tweet = UI.getElementData(e.target)

    container.popover({
      html: true
      placement: "auto right" # Otherwise it goes off the top of the screen
      trigger: "manual"
      container: e.target # Hovering over the popover should hold it open
      # No need for reactivity here since tweet does not change
      content: Blaze.toHTML Blaze.With Datastream.findOne(tweet._id), -> Template.tweetPopup
    }).popover("show")

    container.one("mouseleave", -> container.popover("destroy") )

  "mouseenter .user-pill-container": (e) ->
    container = $(e.target)

    container.popover({
      html: true
      placement: "auto right"
      trigger: "manual"
      container: e.target
      content: ->
        # Grab updated data
        user = UI.getElementData(e.target)
        # Check if we should show chat invite
        if user.status?.online and user._id isnt Meteor.userId()
          return Blaze.toHTML Template.userInvitePopup
        else
          return null
    }).popover("show")

    container.one("mouseleave", -> container.popover("destroy") )

Template.mapper.adminControls = Template.adminControls

Template.mapper.rendered = ->
  # Set initial active tab when state changes
  @comp = Deps.autorun ->
    tab = Session.get('taskView')
    return unless tab?
    $('.stack .pages').removeClass('active')
    $('#mapper-'+tab).addClass('active')

Template.mapper.destroyed = -> @comp.stop()

Template.guidance.message = -> Session.get("guidanceMessage")

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
    when treatment.payment? then Template.tutorialPayment
    when treatment.wage?  then Template.scaledPayment
    else null

Template.pageNav.treatment = TurkServer.treatment

Template.tutorialPayment.amount = -> "$" + @payment.toFixed(2)

Template.scaledPayment.amount = ->
  hours = TurkServer.Timers.activeTime() / (3600000) # millis per hour
  lowest = (@wage * hours).toFixed(2)
  highest = ((@wage + @bonus) * hours).toFixed(2)
  return "$#{lowest} - $#{highest}"

Template.scaledPayment.lowest = -> @wage.toFixed(2)
Template.scaledPayment.highest = -> (@wage + @bonus).toFixed(2)

Template.help.teamInfo = ->
  switch @groupSize
    when 1 then "You are working <b>by yourself</b>. There are no other team members for this task."
    when undefined then "You are working in a <b>team</b>."
    else "You are working in a <b>team of #{@groupSize} members</b>."

Template.help.instructionsInfo = ->
  instr = "Refer to the <b>Instructions</b> document for an overview of the instructions."
  if @groupSize > 1 or not @groupSize?
    instr += " You should feel free to ask your teammates about anything that you don't understand."
  return instr

Template.help.rendered = ->
  this.$(".dropdown > a").click()
