@Mapper ?= {}

Mapper.loadCSVTweets = (file, limit) ->
  # csv is exported by the csv package

  Assets.getText file, (err, res) ->
    throw err if err

    csv()
    .from.string(res, {
        columns: true
        trim: true
      })
    .to.array Meteor.bindEnvironment ( arr, count ) ->

      i = 0
      while i < limit and i < arr.length
        Datastream.insert
          num: i+1 # Indexed from 1
          text: arr[i].text
        i++
      # console.log(i + " tweets inserted")

    , (e) ->
      Meteor._debug "Exception while reading CSV:", e
