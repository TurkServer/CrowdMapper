Template.docTabs.documents = ->
  Documents.find()

Template.docTabs.events =
  "click .action-newdoc": ->
    Documents.insert
      title: "untitled"
    , (err, id) ->
      return unless id
      Session.set("document", id)

  "click a": (e) ->
    e.preventDefault()
    Session.set("document", @_id)

Template.docTab.active = ->
  @_id is Session.get("document")

Template.docCurrent.title = ->
  id = Session.get("document")
  Documents.findOne(id)?.title

Template.docCurrent.document = ->
  Session.get("document")

Template.docCurrent.events =
  "keydown input": (e) ->
    return unless e.keyCode == 13
    e.preventDefault()

    $(e.target).blur()
    id = Session.get("document")
    Documents.update id,
      title: e.target.value

  "click button": ->
    id = Session.get("document")
    Documents.remove(id)
    Session.set("document", null)
