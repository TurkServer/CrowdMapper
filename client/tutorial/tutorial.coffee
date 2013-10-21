Template.mapper.steps = [
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
