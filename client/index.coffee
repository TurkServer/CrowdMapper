login = ->
  return if Meteor.userId()
  console.log "trying login"
  bootbox.prompt "Please enter a username", (username) ->
    Meteor.insecureUserLogin(username) if username?

# Start initial login after stuff loaded
Meteor.startup ->
  Meteor.setTimeout login, 50

# Always request username if logged out
Deps.autorun(login)

# Routing
Router.map ->
  @route('home', {path: '/'})
  @route('mapper')
  @route('admin')

#Router.configure
#  layout: 'layout'
#  renderTemplates:
#    'datastream':
#      to: 'datastream'
#    'sidebar':
#      to: 'sidebar'

Template.userList.usersOnline = ->
  Meteor.users.find()

disconnectDialog = null

Handlebars.registerHelper "userPillById", (userId) ->
  return new Handlebars.SafeString Template.userPill Meteor.users.findOne userId

# Warn when disconnected instead of just sitting there.
Deps.autorun ->
  status = Meteor.status()

  if status.connected and disconnectDialog?
    disconnectDialog.modal("hide")
    disconnectDialog = null
    return

  if !status.connected and disconnectDialog is null
    disconnectDialog = bootbox.dialog(
      """<h3>You have been disconnected from the server.
      Please check your Internet connection.</h3>""")
    return
