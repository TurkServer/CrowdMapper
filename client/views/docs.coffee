Template.docTabs.documents = ->
  Documents.find()

Template.docTabs.events =
  "click .action-newdoc": ->
    Documents.insert
      title: "untitled"

  "click a": (e) ->
    e.preventDefault()
    Session.set("document", @_id)

Template.docTab.active = ->
  @_id is Session.get("document")

Template.docCurrent.document = ->
  Session.get("document")
