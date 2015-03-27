# Collections for analysis
Analysis.People = new Meteor.Collection("analysis.people")
###
  Fields:
  - userId
  - age
  - dropped (whether this user quit)
  - gender
  - exitSurveyWords
  - groupSize (nominalSize of group)
  - instanceId
  - treated
  - tutorialMins
  - tutorialWords
###

# Nominal world stats that don't change over time
Analysis.Worlds = new Meteor.Collection("analysis.worlds")
###
  Fields:
  - batchId
  - completed (whether at least one person submitted)
  - endTime
  - fracFemale
  - nominalSize
  - startTime
  - users
  - treated (valid treatment for analysis)
  - treatments
###

# Stats computed in sliced world states
Analysis.Stats = new Meteor.Collection("analysis.stats")
###
  Fields:
  - instanceId
  - chatFrac / chatWeight
  - chatWordCount / chatWordEntropy
  - avgIndivEntropy
  - classifyFrac / classifyWeight
  - effortEntropy (equality across users)
  - eventContention (maybe)
  - filterFrac / filterWeight
  - fullCreditScore (rounded)
  - groupEntropy (distribution in group)
  - partialCreditScore
  - personTime
  - precision
  - recall
  - totalEffort
  - verifyFrac / verifyWeight
  - wallTime
###

###
  People fields
  - chatWordCount / chatWordFrac
  - dropped (whether dropout happened yet)
  - effort
  - time (activeTime)
  - tutorialMins / tutorialWords
  - wallTime (of group)
  - userId
###

if Meteor.isServer
  Analysis.People._ensureIndex({instanceId: 1, userId: 1})

  # Index stats collection by world/user, then by time
  Analysis.Stats._ensureIndex({instanceId: 1, wallTime: 1}, {sparse: true})
  Analysis.Stats._ensureIndex({userId: 1, wallTime: 1}, {sparse: true})
