steps = [
    template: Template.tut_whatis
  ,    
    template: Template.tut_experiment
  ,    
    template: Template.tut_yourtask
  ,
    spot: ".datastream"
    template: Template.tut_datastream
  ,
    spot: ".navbar"
    template: Template.tut_navbar
  ,
    spot: ".navbar, #mapper-events"
    template: Template.tut_events
    onLoad: -> Mapper.switchTab("events")
  ,
    spot: ".navbar, #mapper-map"
    template: Template.tut_map
    onLoad: -> Mapper.switchTab("map")
  ,
    spot: ".navbar, #mapper-docs"
    template: Template.tut_documents
    onLoad: ->
      Mapper.switchTab("docs")
      unless Session.get("document")?
        # open a doc if there is one
        someDoc = Documents.findOne()
        Session.set("document", someDoc._id) if someDoc?
  ,
    spot: ".user-list"
    template: Template.tut_userlist
  ,
    spot: ".chat-overview"
    template: Template.tut_chatrooms
  ,
    template: Template.tut_actionreview
  ,
    spot: ".datastream"
    template: Template.tut_filterdata
  ,
    spot: "#mapper-events"
    template: Template.tut_editevent
    onLoad: -> Mapper.switchTab("events")
  ,
    spot: ".events-header"
    template: Template.tut_sortevent
  ,
    spot: ".datastream, #mapper-events"
    template: Template.tut_dragdata
    onLoad: -> Mapper.switchTab("events")
  ,
    spot: "#mapper-map"
    template: Template.tut_editmap
    onLoad: -> Mapper.switchTab("map")
  ,
    spot: "#mapper-docs"
    template: Template.tut_editdocs
    onLoad: -> Mapper.switchTab("docs")
  ,
    spot: ".chat-overview"
    template: Template.tut_joinchat
  ,
    spot: ".chat-overview, .chat-messaging"
    template: Template.tut_leavechat
  ,
    spot: ".chat-messaging"
    template: Template.tut_chatting
    onLoad: ->
      unless Session.get("room")?
        # join a chat room there is one
        someRoom = ChatRooms.findOne()
        Session.set("room", someRoom._id) if someRoom?
  ,
    template: Template.tut_groundrules
]

Template.tutorial.created = ->
  @data.tutorial = new Tutorial(steps)

Template.tutorial.rendered = ->
  # Animate spotlight and modal to appropriate positions
  spot = @find(".spotlight")
  modal = @find(".modal")
  tutorial = @data.tutorial

  [spotCSS, modalCSS] = tutorial.getPositions()
  $(spot).animate(spotCSS)
  $(modal).animate(modalCSS)

  return if @initialRendered # Only do the below on first render
  console.log "first tutorial render"

  # attach a window resize handler
  @resizer = ->
    [spotCSS, modalCSS] = tutorial.getPositions()
    # Don't animate, just move
    $(spot).css(spotCSS)
    $(modal).css(modalCSS)

  $(window).on('resize', @resizer)

  # Make modal draggable so it can be moved out of the way if necessary
  # Set an arbitrary scope so it can't be dropped on anything
  $(modal).draggable
    scope: "tutorial-modal"
    containment: "window"

  @initialRendered = true

Template.tutorial.destroyed = ->
  # Take off the resize watcher
  $(window).off('resize', @resizer) if @resizer
  @resizer = null

Template.tutorial.content = ->
  # Run load function, if any
  @tutorial.currentLoadFunc()?()

  @tutorial.currentTemplate()()

Template.tutorial_buttons.events =
  "click .action-tutorial-back": -> @tutorial.prev()
  "click .action-tutorial-next": -> @tutorial.next()

Template.tutorial_buttons.prevDisabled = ->
  unless @tutorial.prevEnabled() then "disabled" else ""
Template.tutorial_buttons.nextDisabled = ->
  unless @tutorial.nextEnabled() then "disabled" else ""

defaultSpot =
  top: 0
  left: 0
  bottom: 0
  right: 0

defaultModal =
  top: "10%"
  left: "50%"
  width: 560
  "margin-left": -280

spotPadding = 10 # How much to expand the spotlight on all sides
modalBuffer = 20 # How much to separate the modal from the spotlight

class Tutorial
  constructor: (@steps) ->
    @step = 0
    @stepDep = new Deps.Dependency

  prev: ->
    return if @step is 0
    @step--
    @stepDep.changed()

  next: ->
    return if @step is (@steps.length - 1)
    @step++
    @stepDep.changed()

  prevEnabled: ->
    @stepDep.depend()
    return @step > 0

  nextEnabled: ->
    @stepDep.depend()
    # TODO don't enable next for certain steps
    return @step < (@steps.length - 1)

  currentTemplate: ->
    @stepDep.depend()
    return @steps[@step].template

  # Stuff below is currently not reactive
  currentLoadFunc: ->
    return @steps[@step].onLoad

  getPositions: ->
    # @stepDep.depend() if we want reactivity
    selector = @steps[@step].spot
    return [ defaultSpot, defaultModal ] unless selector?

    items = $(selector)
    if items.length is 0
      console.log "Tutorial error: couldn't find spot for " + selector
      return [ defaultSpot, defaultModal ]

    # Compute spot and modal positions
    hull =
      top: 5000
      left: 5000
      bottom: 5000
      right: 5000

    items.each (i) ->
      $el = $(this)
      offset = $el.offset()
      hull.top = Math.min(hull.top, offset.top)
      hull.left = Math.min(hull.left, offset.left)
      # outer height/width used here: http://api.jquery.com/outerHeight/
      hull.bottom = Math.min(hull.bottom, $(window).height() - offset.top - $el.outerHeight())
      hull.right = Math.min(hull.right, $(window).width() - offset.left - $el.outerWidth())

    # enlarge spotlight slightly and find largest side
    maxKey = null
    maxVal = 0
    for k,v of hull
      if v > maxVal
        maxKey = k
        maxVal = v
      hull[k] = Math.max(0, v - spotPadding)

    # put modal on the side with the most space
    modal = null
    switch maxKey
      when "top" # go as close to top as possible
        modal = $.extend {}, defaultModal, { top: "5%" }
      when "bottom" # start from bottom of spot
        modal = $.extend {}, defaultModal,
          top: $(window).height() - hull.bottom + modalBuffer
      when "left"
        width = Math.min(hull.left - 2*modalBuffer, defaultModal.width)
        modal = $.extend {}, defaultModal,
          left: hull.left / 2
          width: width
          "margin-left": -width/2
      when "right"
        width = Math.min(hull.right - 2*modalBuffer, defaultModal.width)
        modal = $.extend {}, defaultModal,
          left: $(window).width() - hull.right / 2
          width: width
          "margin-left": -width/2

    return [ hull, modal ]
