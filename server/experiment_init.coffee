replaceURLWithHTMLLinks = (text) ->
  exp = /(\b(https?|ftp|file):\/\/[-A-Z0-9+&@#\/%?=~_|!:,.;]*[-A-Z0-9+&@#\/%=~_|])/ig
  text.replace(exp, "<a href='$1' target='_blank'>$1</a>")

loadDumbTweets = ->
  Assets.getText "tweets_raw_partial.txt", (err, res) ->
    throw err if err
    tweets = replaceURLWithHTMLLinks(res).split("\n")
    _.each tweets, (e, i) ->
      return unless e # Don't insert empty string
      Datastream.insert
        text: e
    console.log(tweets.length + " tweets inserted")

loadCSVTweets = ->
  # csv is exported by the csv package
  limit = 500 # for demo purposes

  Assets.getText "PabloPh_UN_cleaned.csv", (err, res) ->
    throw err if err
    tweets = replaceURLWithHTMLLinks(res)

    csv()
    .from.string(tweets, {
        columns: true
        trim: true
      })
    .to.array Meteor.bindEnvironment ( arr, count ) ->

      i = 0
      while i < limit
        Datastream.insert
          num: i # Keeps things in time order
          text: arr[i].text
        i++
      console.log(i + " tweets inserted")

    , (e) ->
      Meteor._debug "Exception while reading CSV:", e

loadTutorialTweets = ->
  Datastream.insert
    num: 1
    text: "some fake data"

  Datastream.insert
    num: 2
    text: "some more fake data"

  Datastream.insert
    num: 3
    text: "some additional fake data"

TurkServer.initialize ->
  return if Datastream.find().count() > 0

  if @treatment is "tutorial" or @treatment is "recruiting"
    loadTutorialTweets()
  else
    # Load initial tweets on first start
    # loadDumbTweets()
    loadCSVTweets()
