
class AdminController extends RouteController
  onBeforeAction: ->
    unless TurkServer.isAdmin()
      @render("loadError")
    else
      @next()

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
    path: '/replay/:instance/:speed?/:scroll?'
    template: 'mapper',
    controller: AdminController
    waitOn: ->
      speed = parseFloat(this.params.speed) || 20
      Meteor.subscribe "replay", this.params.instance, speed, ->
        Session.set("userSubReady", true)
        Session.set("dataSubReady", true)
        # Session.set("docSubReady", true)
        Session.set("eventSubReady", true)

        Session.set("chatSubReady", true)
        Session.set("chatRoomReady", true)

    onAfterAction: ->
      # Set displayed chat room upon arrival of any message.
      # This just filters the chat collection based on the room, and shouldn't
      # be too slow because most worlds only had one room.
      @chatWatcher = ChatMessages.find().observeChanges
        added: (id, fields) -> Session.set("room", fields.room)

      return unless this.params.scroll
      # turn on auto scrolling for new events and hidden tweets
      @dataWatcher = Datastream.find({hidden: $exists: false}).observeChanges
        removed: (id) -> Mapper.scrollToData(id, 100)

      @eventWatcher = Events.find().observeChanges
        added: (id) ->
          Deps.afterFlush -> Mapper.scrollToEvent(id, 100)

    onStop: ->
      @chatWatcher?.stop()
      @dataWatcher?.stop()
      @eventWatcher?.stop()

Template.adminControls.events
  "change input": (e, t) ->
    Session.set("adminShowDeleted", e.target.checked)

Template.adminControls.helpers
  showDeleted: -> Session.equals("adminShowDeleted", true)
  remainingData: -> Datastream.find({
      $or: [ { events: null }, { events: {$size: 0} } ],
      hidden: null
    }).count()

  hiddenData: -> Datastream.find({ hidden: true }).count()

  attachedData: -> Datastream.find({
      "events.0": $exists: true
    }).count()

  createdEvents: -> Events.find({deleted: null}).count()
  deletedEvents: -> Events.find({deleted: true}).count()
