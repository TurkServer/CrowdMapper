Meteor.startup ->
  console.log 'Started at ' + location.href

Meteor.insecureUserLogin = (username, callback) ->
  Accounts.callLoginMethod
    methodArguments: [{username: username}],
    userCallback: callback

# Request username if not logged in
Deps.autorun ->
  return if Meteor.userId()

  console.log "trying login"

  bootbox.prompt "Please enter a username", (username) ->
    Meteor.insecureUserLogin(username) if username?

Meteor.Router.add
  '/': 'home',
  '/map': 'map',
  '/events': 'events'

Template.pages.events =
  "click a[data-target='events']": -> Meteor.Router.to("/events")
  "click a[data-target='map']": -> Meteor.Router.to("/map")

