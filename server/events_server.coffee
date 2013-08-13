# Create an index on events to delete editors who piss off
Events._ensureIndex
  editor: 1

UserStatus.on "sessionLogout", (userId, _) ->
  Events.update { editor: userId },
    $unset: { editor: null }
  , multi: true
