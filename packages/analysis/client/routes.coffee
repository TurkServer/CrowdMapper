# This controller handles the behavior of all admin templates
# TODO: it doesn't belong in the analysis package, but we use it here.
class AdminController extends RouteController
  onBeforeAction: (pause) ->
    unless TurkServer.isAdmin()
      @render("loadError")
      pause()

Router.map ->
  # Single-instance visualization templates
  @route 'viz',
    path: 'viz/:groupId'
    controller: AdminController
    waitOn: ->
      @readyDep = new Deps.Dependency
      @readyDep.isReady = false;

      Meteor.call "cm-get-viz-data", this.params.groupId, (err, res) =>
        bootbox.alert(err) if err

        this.mapperData = res

        @readyDep.isReady = true;
        @readyDep.changed()

      return {
      ready: =>
        @readyDep.depend()
        return @readyDep.isReady
      }
    data: ->
      @readyDep.depend()
      return this.mapperData
    action: ->
      this.render() if this.ready()

  @route 'overview',
    controller: AdminController
    layoutTemplate: "overviewLayout"
    action: ->

      # Overview route, with access to experiments and stuff
      # TODO reduce repetitive loading code below
  @route 'overviewTagging',
    path: 'overview/tagging'
    controller: AdminController
    layoutTemplate: "overviewLayout"
    waitOn: ->
      loaded = @loaded = new Tracker.Dependency
      isReady = false

      Meteor.call "cm-get-group-cooccurences", (err, res) =>
        bootbox.alert(err) if err

        this.data = res

        isReady = true
        loaded.changed()

      return {
      ready: ->
        loaded.depend()
        return isReady
      }
    data: ->
      @loaded.depend()
      return this.data
    action: ->
      this.render() if this.ready()

  @route 'overviewGroupPerformance',
    path: 'overview/groupPerformance'
    controller: AdminController
    layoutTemplate: "overviewLayout"
    waitOn: ->
      loaded = @loaded = new Tracker.Dependency
      isReady = false

      Meteor.call "cm-get-analysis-worlds", (err, res) =>
        bootbox.alert(err) if err

        this.data = res

        isReady = true
        loaded.changed()

      return {
      ready: ->
        loaded.depend()
        return isReady
      }
    data: ->
      @loaded.depend()
      return this.data
    action: ->
      this.render() if this.ready()
