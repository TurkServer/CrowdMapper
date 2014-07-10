Meteor.startup ->
  # No session document by default
  Session.setDefault("document", undefined)

Template.docs.loaded = -> Session.equals("docSubReady", true)

Template.docTabs.documents = ->
  selector = if TurkServer.isAdmin() and Session.equals("adminShowDeleted", true) then {}
  else { deleted: {$exists: false} }
  Documents.find(selector)

Template.docTabs.noDocuments = ->
  Documents.find(deleted: {$exists: false}).count() is 0

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

Template.docTab.active = -> if Session.equals("document", @_id) then "active" else ""
Template.docTab.deleted = -> if @deleted then "deleted" else ""

Template.docCurrent.document = UI.emboxValue ->
  id = Session.get("document")
  # Can't stay in a document if someone deletes it, unless we're admin
  selector = {_id: id}
  selector.deleted = {$exists: false} unless TurkServer.isAdmin()

  if Documents.findOne(selector)
    return id
  else
    return undefined

Template.docCurrent.title = -> Documents.findOne(""+@)?.title

# TODO a hack to forcibly re-render the editable to re-render doc or title changes
# It only works because if doc didn't change, title must have (no other fields)
Template.docCurrent.docTitleComponent = ->
  UI.Component.extend
    kind: "mapperDocTitle",
    render: -> Template.docTitle

Template.docTitle.rendered = ->
  @editComp = @$(".editable").editable
    display: ->
    success: (response, newValue) ->
      docId = Session.get("document")
      return unless document
      Meteor.call "renameDocument", docId, newValue

# This is needed to take out the editable when doc/title changes
Template.docTitle.destroyed = ->
  @editComp.editable("destroy")

Template.docCurrent.events =
  "click .action-document-delete": ->
    bootbox.confirm "Deleting this document will kick out all other editors! Are you sure?", (res) ->
      return unless res
      id = Session.get("document")
      Meteor.call "deleteDocument", id
      Session.set("document", undefined)

Template.docCurrent.config = ->
  (editor) ->
    editor.setReadOnly(true) if TurkServer.isAdmin()
    # Set some reasonable options on the editor
    editor.setShowPrintMargin(false)
    editor.getSession().setUseWrapMode(true)
