Meteor.startup ->
  # No session document by default
  Session.setDefault("document", undefined)

Template.docs.loaded = -> Session.equals("docSubReady", true)

Template.docTabs.documents = ->
  Documents.find()

Template.docTabs.noDocuments = ->
  Documents.find().count() is 0

Template.docTabs.events =
  "click .action-document-new": ->
    bootbox.prompt "Name the document", (docName) ->
      return unless !!docName

      Meteor.call "createDocument", docName, (err, id) ->
        return unless id
        Session.set("document", id)

  "click a": (e) ->
    e.preventDefault()
    Session.set("document", @_id)

    TurkServer.log
      action: "document-open"
      docId: @_id

Template.docTab.active = ->
  @_id is Session.get("document")

Template.docTitle.rendered = ->
  @$(".editable").editable
    display: ->
    success: (response, newValue) ->
      docId = Session.get("document")
      return unless document
      Meteor.call "renameDocument", docId, newValue

Template.docCurrent.document = ->
  id = Session.get("document")
  # Can't stay in a document if someone deletes it! Don't do reactive or this causes re-render on title change.
  return if Documents.findOne(id, {reactive: false}) then id else undefined

Template.docCurrent.events =
  "click .action-document-delete": ->
    bootbox.confirm "Deleting this document will kick out all other editors! Are you sure?", (res) ->
      return unless res
      id = Session.get("document")
      Meteor.call "deleteDocument", id
      Session.set("document", undefined)

Template.docCurrent.config = ->
  (editor) ->
    # Set some reasonable options on the editor
    editor.setShowPrintMargin(false)
    editor.getSession().setUseWrapMode(true)

Template.docTitle.title = -> Documents.findOne(""+@)?.title
