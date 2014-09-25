# This controller handles the behavior of all admin templates
class AdminController extends RouteController
  onBeforeAction: (pause) ->
    unless TurkServer.isAdmin()
      @render("loadError")
      pause()

# Admin Routes
Router.map ->
  # Multi-watching capable route
  @route 'watch',
    path: '/watch/:instance'
    template: 'mapper',
    controller: AdminController
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
    controller: AdminController
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

  # Single-instance visualization templates
  @route 'viz',
    path: 'viz/:groupId'
    controller: AdminController
    waitOn: ->
      @readyDep = new Deps.Dependency
      @readyDep.isReady = false;

      Meteor.call "getMapperData", this.params.groupId, (err, res) =>
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


Template.adminControls.events
  "change input": (e, t) ->
    Session.set("adminShowDeleted", e.target.checked)

Template.adminControls.showDeleted = -> Session.equals("adminShowDeleted", true)

Template.adminControls.remainingData = -> Datastream.find({
    $or: [ { events: null }, { events: {$size: 0} } ],
    hidden: null
  }).count()

Template.adminControls.hiddenData = -> Datastream.find({ hidden: true }).count()

Template.adminControls.attachedData = -> Datastream.find({
    "events.0": $exists: true
  }).count()

Template.adminControls.createdEvents = -> Events.find({deleted: null}).count()

Template.adminControls.deletedEvents = -> Events.find({deleted: true}).count()
