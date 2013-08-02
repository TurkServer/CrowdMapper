Meteor.startup ->
  # Clear all users stored in chatrooms
  ChatUsers.remove({})

  ChatRooms.update {},
    $set:
      {users: 0}
  , multi: true

