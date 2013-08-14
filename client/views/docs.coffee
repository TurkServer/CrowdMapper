Meteor.startup ->
  # Remove any session document
  Session.set("document", null)

Template.docTabs.documents = ->
  Documents.find()

Template.docTabs.noDocuments = ->
  Documents.find().count() is 0

Template.docTabs.events =
  "click .action-document-new": ->
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

Template.docTitle.rendered = ->
  settings =
    success: (response, newValue) ->
      docId = Session.get("document")
      return unless document
      Documents.update docId,
        $set: { title: newValue }

  $(@find('.editable:not(.editable-click)')).editable('destroy').editable(settings)

Template.docTitle.title = ->
  id = Session.get("document")
  Documents.findOne(id)?.title

Template.docCurrent.document = ->
  id = Session.get("document")
  # Can't stay in a document if someone deletes it! Don't do reactive or this causes re-render on title change.
  return if Documents.findOne(id, {reactive: false}) then id else `undefined`

Template.docCurrent.events =
  "click .action-document-delete": ->
    bootbox.confirm "Deleting this document will kick out all other editors! Are you sure?", (res) ->
      return unless res
      id = Session.get("document")
      Documents.remove(id)
      Session.set("document", null)

Template.docCurrent.config = ->
  (editor) ->
    # Set some reasonable options on the editor
    editor.setShowPrintMargin(false)
    editor.getSession().setUseWrapMode(true)
