Meteor.startup ->
  # No session document by default
  Session.setDefault("document", undefined)

Template.docs.helpers
  loaded: -> Session.equals("docSubReady", true)

Template.docTabs.helpers
  documents: ->
    selector = if TurkServer.isAdmin() and Session.equals("adminShowDeleted", true) then {}
    else { deleted: {$exists: false} }
    Documents.find(selector)

  noDocuments: ->
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

Template.docTab.helpers
  active: -> if Session.equals("document", @_id) then "active" else ""
  deleted: -> if @deleted then "deleted" else ""

# TODO: make sure this doesn't cause thrashing of the currently open document.
Template.docCurrent.helpers
  document: ->
    id = Session.get("document")
    # Can't stay in a document if someone deletes it, unless we're admin
    selector = {_id: id}
    selector.deleted = {$exists: false} unless TurkServer.isAdmin()

    if Documents.findOne(selector)
      return id
    else
      return undefined

  title: -> Documents.findOne(""+@)?.title

Template.docTitle.rendered = ->
  tmplInst = this

  this.autorun ->
    # Trigger this whenever title changes
    title = Blaze.getData()
    # Destroy old editable if it exists
    tmplInst.$(".editable").editable("destroy").editable
      display: ->
      success: (response, newValue) ->
        docId = Session.get("document")
        return unless document
        Meteor.call "renameDocument", docId, newValue

Template.docCurrent.events =
  "click .action-document-delete": ->
    bootbox.confirm "Deleting this document will kick out all other editors! Are you sure?", (res) ->
      return unless res
      id = Session.get("document")
      Meteor.call "deleteDocument", id
      Session.set("document", undefined)

aceConfig = (ace) ->
  # Set some reasonable options on the editor
  ace.setShowPrintMargin(false)
  # ace.renderer.setShowGutter(false)
  ace.session.setUseWrapMode(true)
  ace.session.setMode("ace/mode/markdown")

aceCheckAdmin = (ace) ->
  ace.setReadOnly(true) if TurkServer.isAdmin()

Template.docCurrent.helpers
  config: -> aceConfig
  checkAdmin: -> aceCheckAdmin
