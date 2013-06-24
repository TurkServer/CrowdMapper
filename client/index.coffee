login = ->
  return if Meteor.userId()
  console.log "trying login"
  bootbox.prompt "Please enter a username", (username) ->
    Meteor.insecureUserLogin(username) if username?

Meteor.startup ->
  console.log 'Started at ' + location.href
  login()

# Request username if logged out
Deps.autorun(login)

Meteor.Router.add
  '/': 'home',
  '/map': 'map',
  '/events': 'events'

Template.pages.events =
  "click a[data-target='events']": -> Meteor.Router.to("/events")
  "click a[data-target='map']": -> Meteor.Router.to("/map")

