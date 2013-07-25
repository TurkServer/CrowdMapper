login = ->
  return if Meteor.userId()
  console.log "trying login"
  bootbox.prompt "Please enter a username", (username) ->
    Meteor.insecureUserLogin(username) if username?

Meteor.startup ->
  login()

# Request username if logged out
Deps.autorun(login)

Router.map ->
  @route('home', {path: '/'})
  @route('map')
  @route('events')
  @route('docs')

Template.pages.events =
  "click a[data-target='docs']": -> Router.go("/docs")
  "click a[data-target='events']": -> Router.go("/events")
  "click a[data-target='map']": -> Router.go("/map")

