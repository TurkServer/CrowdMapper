steps = [
  {
    spot: null
    template: Template.tut_whatis
  },
  {
    spot: null
    template: Template.tut_experiment
  }
]

Template.tutorial.created = ->
  @data.tutorial = new Tutorial(steps)

Template.tutorial.rendered = ->
  # Animate spotlight and modal to appropriate positions
  spot = @find(".spotlight")
  modal = @find(".modal")

  [spotCSS, modalCSS] = @data.tutorial.getPositions()
  $(spot).animate(spotCSS);
  $(modal).animate(modalCSS);

Template.tutorial.content = ->
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
  width: "560px"
  "margin-left": "-280px"

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

  getPositions: ->
    # @stepDep.depend() if we want reactivity
    selector = @steps[@step].spot
    return [ defaultSpot, defaultModal ] if selector is null

    # Compute spot and modal positions
    hull =
      top: 4000
      left: 4000
      bottom: 4000
      right: 4000

    $(selector).each (i) ->
      $el = $(this)
      offset = $el.offset()
      hull.top = Math.min(hull.top, offset.top)
      hull.left = Math.min(hull.left, offset.left)
      hull.bottom = Math.min(hull.bottom, $(window).height() - offset.top - $el.height())
      hull.right = Math.min(hull.right, $(window).width() - offset.left - $el.width())

    # TODO compute modal position
    return [ hull, null ]
