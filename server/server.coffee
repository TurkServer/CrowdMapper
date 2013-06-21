
Accounts.registerLoginHandler (loginRequest) ->
  return unless loginRequest.username

  user = Meteor.users.findOne
    username: loginRequest.username

  unless user
    userId = Meteor.users.insert
      username: loginRequest.username
  else
    userId = user._id;

  stampedToken = Accounts._generateStampedLoginToken();
  Meteor.users.update userId,
    $push: {'services.resume.loginTokens': stampedToken}

  return {
    id: userId,
    token: stampedToken.token
  }

Meteor.startup ->
  # code to run on server at startup
  # console.log "server started"
