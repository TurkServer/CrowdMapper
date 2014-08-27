TurkServer.initialize ->
  return if Datastream.find().count() > 0

  if @instance.treatment().tutorialEnabled
    Mapper.loadCSVTweets("tutorial.csv", 10)
  else
    # Load initial tweets on first start
    # Meta-cleaned version has 1567 tweets
    Mapper.loadCSVTweets("PabloPh_UN_cm.csv", 2000)
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
