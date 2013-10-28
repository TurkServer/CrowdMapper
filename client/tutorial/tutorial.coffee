openDocument = ->
  unless Session.get("document")?
    # open a doc if there is one
    someDoc = Documents.findOne()
    Session.set("document", someDoc._id) if someDoc?

joinChatroom = ->
  unless Session.get("room")?
    # join a chat room there is one
    someRoom = ChatRooms.findOne()
    Session.set("room", someRoom._id) if someRoom?

tutorialSteps = [
    template: Template.tut_whatis
  ,    
    template: Template.tut_experiment
  ,    
    template: Template.tut_yourtask
  ,
    spot: ".datastream"
    template: Template.tut_datastream
  ,
    spot: ".datastream"
    template: Template.tut_filterdata
  ,
    spot: ".navbar"
    template: Template.tut_navbar
  ,
    spot: ".navbar, #mapper-events"
    template: Template.tut_events
    onLoad: -> Mapper.switchTab("events")
  ,
    spot: "td.event-create"
    template: Template.tut_create_event
    onLoad: ->
      Mapper.switchTab("events")
      # buttonDiv = $("td.event-create")
      # TODO use the position of the button instead of this hack
      $(".events-body.scroll-vertical").scrollTop(50000)
  ,
    spot: ".datastream, #mapper-events"
    template: Template.tut_dragdata
    onLoad: -> Mapper.switchTab("events")
  ,
    spot: ".events-header tr > th:eq(0), .events-body tr > td:nth-child(1):not(.event-create)"
    template: Template.tut_events_index
    onLoad: -> Mapper.switchTab("events")
  ,
    spot: ".events-header tr > th:eq(1), .events-body tr > td:nth-child(2)"
    template: Template.tut_events_sources
    onLoad: -> Mapper.switchTab("events")
  ,
    spot: ".events-header tr > th:eq(2), .events-body tr > td:nth-child(3)"
    template: Template.tut_events_type
    onLoad: -> Mapper.switchTab("events")
  ,
    spot: ".events-header tr > th:eq(3), .events-body tr > td:nth-child(4)"
    template: Template.tut_events_description
    onLoad: -> Mapper.switchTab("events")
  ,
    spot: ".events-header tr > th:eq(4), .events-body tr > td:nth-child(5)"
    template: Template.tut_events_region
    onLoad: -> Mapper.switchTab("events")
  ,
    spot: ".events-header tr > th:eq(5), .events-body tr > td:nth-child(6)"
    template: Template.tut_events_province
    onLoad: -> Mapper.switchTab("events")
  ,
    spot: ".events-header tr > th:eq(6), .events-body tr > td:nth-child(7)"
    template: Template.tut_events_location
    onLoad: -> Mapper.switchTab("events")
  ,
    spot: "#mapper-events"
    template: Template.tut_editevent
    onLoad: -> Mapper.switchTab("events")
  ,
    spot: ".datastream, #mapper-events"
    template: Template.tut_addtweet
    onLoad: -> Mapper.switchTab("events")
  ,
    spot: ".events-header"
    template: Template.tut_sortevent
  ,
    spot: ".navbar, #mapper-map"
    template: Template.tut_map
    onLoad: -> Mapper.switchTab("map")
  ,
    spot: ".olControlPanZoomBar > *"
    template: Template.tut_mapcontrols
    onLoad: -> Mapper.switchTab("map")
  ,
    spot: "#mapper-map"
    template: Template.tut_editmap
    onLoad: -> Mapper.switchTab("map")
  ,
    spot: "#mapper-map"
    template: Template.tut_maplocation
    onLoad: -> Mapper.switchTab("events")
  ,
    spot: ".navbar, #mapper-docs"
    template: Template.tut_documents
    onLoad: ->
      Mapper.switchTab("docs")
      openDocument()
  ,
    spot: "#mapper-docs"
    template: Template.tut_editdocs
    onLoad: -> Mapper.switchTab("docs")
  ,
    spot: ".user-list"
    template: Template.tut_userlist
  ,
    spot: ".chat-overview"
    template: Template.tut_chatrooms
  ,
    spot: ".notification"
    template: Template.tut_notifications
  ,
    spot: ".chat-overview"
    template: Template.tut_joinchat
  ,
    spot: ".chat-overview, .chat-messaging"
    template: Template.tut_leavechat
    onLoad: joinChatroom
  ,
    spot: ".chat-messaging"
    template: Template.tut_chatting
  ,
    template: Template.tut_groundrules
  ,
    template: Template.tut_end
]

Template.tutorial.options =
  steps: tutorialSteps
  onFinish: -> Router.go("/mapper")
