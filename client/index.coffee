if Meteor.isClient
  Template.hello.greeting = ->
    return "Welcome to CrowdMapper."

  Template.hello.events
    'click input' : ->
      # template data, if any, is available in 'this'
      console.log("You pressed the button") if console?


