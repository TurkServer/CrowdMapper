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

