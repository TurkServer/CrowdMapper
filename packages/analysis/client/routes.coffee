adminRedirectURL = null

# This controller handles the behavior of all admin templates
class AdminController extends RouteController
  onRun: ->
    unless TurkServer.isAdmin()
      # Redirect to turkserver admin login
      adminRedirectURL = Router.current().url
      Router.go("/turkserver")
    else
      this.next()

# Redirect to the appropriate path after login, if it was set; then remove.
Tracker.autorun ->
  if Meteor.userId() and TurkServer.isAdmin() and adminRedirectURL?
      Router.go(adminRedirectURL)
      adminRedirectURL = null

# TODO fix hack below that is used to avoid hitting the server twice
# https://github.com/EventedMind/iron-router/issues/1011 and related
class AdminDataController extends AdminController
  waitOn: ->
    return if @data()?

    args = @route.options.methodArgs.call(this)
    console.log "getting data"

    # Tack on callback argument
    args.push (err, res) =>
      bootbox.alert(err) if err
      console.log "got data"
      @state.set("data", res)

    Meteor.call.apply(null, args)

    return => @data()?

  data: -> @state.get("data")

Router.map ->
  # Single-instance visualization templates
  @route 'viz',
    path: 'viz/:groupId/:type?/:layout?'
    controller: AdminDataController
    methodArgs: -> [ "cm-get-viz-data", this.params.groupId ]

  # Overview route, with access to experiments and stuff
  @route 'overview',
    controller: AdminController
    layoutTemplate: "overviewLayout"

  @route 'overviewExperiments',
    path: 'overview/experiments'
    controller: AdminController
    layoutTemplate: "overviewLayout"
    waitOn: ->
      Meteor.subscribe("cm-analysis-worlds", {
        pseudo: null,
        synthetic: null
      })

  @route 'overviewPeople',
    path: 'overview/people'
    controller: AdminController
    layoutTemplate: "overviewLayout"
    waitOn: -> Meteor.subscribe("cm-analysis-people")

  @route 'overviewTagging',
    path: 'overview/tagging'
    controller: AdminDataController
    layoutTemplate: "overviewLayout"
    methodArgs: -> [ "cm-get-group-cooccurences" ]

  @route 'overviewStats',
    path: 'overview/stats'
    controller: AdminDataController
    layoutTemplate: "overviewLayout"
    methodArgs: -> [ "cm-get-action-weights" ]

  @route 'overviewGroupScatter',
    path: 'overview/groupScatter'
    controller: AdminController
    layoutTemplate: "overviewLayout"
    waitOn: ->
      Meteor.subscribe("cm-analysis-worlds", {
        pseudo: null,
        synthetic: null
      })

  @route 'overviewGroupPerformance',
    path: 'overview/groupPerformance'
    controller: AdminController
    layoutTemplate: "overviewLayout"
    waitOn: ->
      Meteor.subscribe("cm-analysis-worlds")

  @route 'overviewGroupSlices',
    path: 'overview/groupSlices'
    controller: AdminController
    layoutTemplate: "overviewLayout"
    waitOn: ->
      Meteor.subscribe("cm-analysis-worlds", {
        pseudo: null,
        synthetic: null
      })

  @route 'overviewIndivPerformance',
    path: 'overview/indivPerformance'
    controller: AdminController
    layoutTemplate: "overviewLayout"
    waitOn: -> Meteor.subscribe("cm-analysis-people")
