# Collections for analysis
Analysis.Worlds = new Meteor.Collection("analysis.worlds")
Analysis.People = new Meteor.Collection("analysis.people")
Analysis.Stats = new Meteor.Collection("analysis.stats")

if Meteor.isServer
  Analysis.People._ensureIndex({instanceId: 1, userId: 1})
