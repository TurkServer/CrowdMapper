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
    template: "tut_welcome"
  ,
    template: "tut_whatis"
  ,    
    template: "tut_project"
  ,    
    template: "tut_yourtask"
  ,
    spot: ".datastream"
    template: "tut_datastream"
  ,
    spot: ".datastream"
    template: "tut_filterdata"
    require:
      event: "data-hide"
  ,
    spot: ".navbar"
    template: "tut_navbar"
  ,
    spot: ".navbar, #mapper-events"
    template: "tut_events"
    onLoad: -> Mapper.switchTab("events")
  ,
    spot: "#mapper-events"
    template: "tut_event_description"
    onLoad: -> Mapper.switchTab("events")
  ,
    spot: ".event-create"
    template: "tut_create_event"
    onLoad: ->
      Mapper.switchTab("events")
    require:
      event: "event-create"
  ,
    spot: "#mapper-events"
    template: "tut_editevent"
    onLoad: -> Mapper.switchTab("events")
    require:
      event: "event-edit"
  ,
    spot: ".events-header tr > th:eq(0), .events-body tr > td:nth-child(1)"
    template: "tut_events_index"
    onLoad: -> Mapper.switchTab("events")
  ,
    spot: ".events-header tr > th:eq(1), .events-body tr > td:nth-child(2), .datastream"
    template: "tut_events_sources"
    onLoad: -> Mapper.switchTab("events")
    require:
      event: "data-link"
  ,
    spot: ".events-header tr > th:eq(2), .events-body tr > td:nth-child(3)"
    template: "tut_events_type"
    onLoad: -> Mapper.switchTab("events")
    require:
      event: "event-update-type"
  ,
    spot: ".events-header tr > th:eq(3), .events-body tr > td:nth-child(4)"
    template: "tut_events_description"
    onLoad: -> Mapper.switchTab("events")
    require:
      event: "event-update-description"
  ,
    spot: ".events-header tr > th:eq(4), .events-body tr > td:nth-child(5)"
    template: "tut_events_region"
    onLoad: -> Mapper.switchTab("events")
    require:
      event: "event-update-region"
  ,
    spot: ".events-header tr > th:eq(5), .events-body tr > td:nth-child(6)"
    template: "tut_events_province"
    onLoad: -> Mapper.switchTab("events")
    # No required event here.
  ,
    spot: ".events-header tr > th:eq(6), .events-body tr > td:nth-child(7)"
    template: "tut_events_location"
    onLoad: -> Mapper.switchTab("events")
  ,
    spot: ".datastream, #mapper-events"
    template: "tut_addtweet"
    onLoad: -> Mapper.switchTab("events")
  ,
    spot: ".events-header"
    template: "tut_sortevent"
    onLoad: -> Mapper.switchTab("events")
  ,
    spot: ".navbar, #mapper-map"
    template: "tut_map"
    onLoad: -> Mapper.switchTab("map")
  ,
    spot: ".olControlPanZoomBar > *"
    template: "tut_mapcontrols"
    onLoad: -> Mapper.switchTab("map")
  ,
    spot: ".navbar, #mapper-events"
    template: "tut_maplocate"
    onLoad: -> Mapper.switchTab("events")
    require:
      event: "event-update-location"
  ,
    spot: "#mapper-map"
    template: "tut_editmap"
    onLoad: -> Mapper.switchTab("map")
  ,
    spot: "#mapper-events"
    template: "tut_maplocation"
    onLoad: -> Mapper.switchTab("events")
    require:
      event: "event-save"
  ,
    spot: "#mapper-events"
    template: "tut_verify"
    onLoad: -> Mapper.switchTab("events")
    require:
      event: "event-vote"
  ,
    spot: ".navbar, #mapper-docs"
    template: "tut_documents"
    onLoad: -> Mapper.switchTab("docs")
    require:
      event: "document-create"
  ,
    spot: "#mapper-docs"
    template: "tut_editdocs"
    onLoad: ->
      Mapper.switchTab("docs")
      openDocument()
  ,
    spot: ".user-list"
    template: "tut_userlist"
  ,
    spot: ".chat-overview"
    template: "tut_chatrooms"
    require:
      event: "chat-create"
  ,
    spot: ".notification"
    template: "tut_notifications"
  ,
    spot: ".chat-overview"
    template: "tut_joinchat"
    require:
      event: "chat-join"
  ,
    spot: ".chat-overview, .chat-messaging"
    template: "tut_leavechat"
    onLoad: joinChatroom
  ,
    spot: ".chat-messaging"
    template: "tut_chatting"
    require:
      event: "chat-message"
]

getRecruitingSteps = ->
  # replace templates with _recruiting if they exist
  # Don't modify original objects to avoid errors
  copiedSteps = $.map(tutorialSteps, (obj) -> $.extend({}, obj))

  for i, step of copiedSteps
    recruitingTemplate = step.template + "_recruiting"
    step.template = recruitingTemplate if Template[recruitingTemplate]

  return copiedSteps.concat [
    spot: ".payment"
    template: "tut_payment_recruiting"
  ,
    template: "tut_end_recruiting"
  ]
  
getTutorialSteps = ->
  return tutorialSteps.concat [
      template: "tut_groundrules"
    ,
      spot: ".payment"
      template: "tut_payment"
    ,
      template: "tut_end"
  ]

Template.mapperTutorial.tutorialEnabled = ->
  treatment = TSConfig.findOne("treatment")?.value 
  return (treatment is "tutorial" or treatment is "recruiting") and not Meteor.user()?.admin

Template.mapperTutorial.options = ->
  treatment = TSConfig.findOne("treatment")?.value
  
  return {
    steps: if treatment is "recruiting" then getRecruitingSteps() else getTutorialSteps()
    emitter: Mapper.events
    onFinish: -> Router.go("/mapper")
  }

# Handy function to allow the entire tutorial
Mapper.bypassTutorial = ->
  for i, step of tutorialSteps
    Mapper.events.emit(step.require.event) if step?.require?.event
  return
