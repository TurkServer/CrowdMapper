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

