loadCSVTweets = (file, limit) ->
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

TurkServer.initialize ->
  return if Datastream.find().count() > 0

  if @instance.treatment().tutorialEnabled
    loadCSVTweets("tutorial.csv", 10)
  else
    # Load initial tweets on first start
    loadCSVTweets("PabloPh_UN_cm.csv", 500)
    # Create a seed instructions document for the app
    docId = Documents.insert
      title: "Instructions"

    Assets.getText "seed-instructions.txt", (err, res) ->
      if err?
        console.log "Error getting document"
        return
      ShareJS.initializeDoc(docId, res)

TurkServer.onConnect ->
  if @instance.treatment().tutorialEnabled
    # Help the poor folks who shot themselves in the foot
    # TODO do a more generalized restore
    Datastream.update({}, {$unset: hidden: null}, {multi: true})
