Meteor.startup ->
  console.log 'Started at ' + location.href

Meteor.insecureUserLogin = (username, callback) ->
  Accounts.callLoginMethod
    methodArguments: [{username: username}],
    userCallback: callback

# Request username if not logged in
Deps.autorun ->
  return if Meteor.userId()

  while not username
    username = window.prompt("Please enter a username", "Guest")

  Meteor.insecureUserLogin(username)

Meteor.Router.add
  '/': 'home',
  '/map': 'map',
  '/events': 'events'

Template.pages.events =
  "click a[data-target='events']": -> Meteor.Router.to("/events")
  "click a[data-target='map']": -> Meteor.Router.to("/map")

