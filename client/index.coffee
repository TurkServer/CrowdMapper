login = ->
  return if Meteor.userId()
  console.log "trying login"
  bootbox.prompt "Please enter a username", (username) ->
    Meteor.insecureUserLogin(username) if username?

# Start initial login after stuff loaded
Meteor.startup ->
  # login()
  Meteor.setTimeout login, 50

# Always request username if logged out
Deps.autorun(login)

# Routing
Router.configure
  notFoundTemplate: 'home'
  # loadingTemplate: 'spinner' # TODO get a spinner here

Router.map ->
  @route('home', {path: '/'})
  @route 'mapper',
    template: 'mapperContainer'
    path: '/mapper/:tutorial?'
    ###
      Can't do this due to https://github.com/EventedMind/iron-router/issues/336
      So we subscribe to EventFields statically right now.
    ###
    # waitOn: -> Meteor.subscribe("eventFieldData")
    # before: Mapper.processSources
    data: -> { tutorialEnabled: @params.tutorial is "tutorial" }
  @route('admin')

#Router.configure
#  layout: 'layout'
#  renderTemplates:
#    'datastream':
#      to: 'datastream'
#    'sidebar':
#      to: 'sidebar'

disconnectDialog = null

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
