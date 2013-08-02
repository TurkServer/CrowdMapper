replaceURLWithHTMLLinks = (text) ->
  exp = /(\b(https?|ftp|file):\/\/[-A-Z0-9+&@#\/%?=~_|!:,.;]*[-A-Z0-9+&@#\/%=~_|])/ig
  text.replace(exp, "<a href='$1' target='_blank'>$1</a>")

Meteor.startup ->
  return if Datastream.find().count() > 0

  # Load initial tweets on first start
  Assets.getText "tweets_raw_partial.txt", (err, res) ->
    throw err if err
    tweets = replaceURLWithHTMLLinks(res).split("\n")
    _.each tweets, (e, i) ->
      Datastream.insert
        text: e
    console.log(tweets.length + " tweets inserted")
