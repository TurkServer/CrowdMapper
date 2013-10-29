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
          _id: i.toString() # Keeps things in time order
          text: arr[i].text
        i++
      console.log(i + " tweets inserted")

    , (e) ->
      Meteor._debug "Exception while reading CSV:", e

loadEventFields = ->
  EventFields.insert
    "key": "type",
    "name": "Type",
    "order": 1,
    "type": "dropdown",
    "choices": [
      "Damaged bridges",
      "Damaged crops",
      "Damaged hospitals/health facilities",
      "Damaged housing",
      "Damaged roads",
      "Damaged schools",
      "Damaged vehicles",
      "Damaged infrastructure (other)",
      "Death(s) reported",
      "Displaced population",
      "Evacuation center",
      "Flooding"
    ]

  EventFields.insert
    "key": "description",
    "name": "Description",
    "order": 2,
    "type": "text"

  EventFields.insert
    "key": "region",
    "name": "Region",
    "order": 3,
    "type": "dropdown",
    "choices": [
      "ARMM - Autonomous Region in Muslim Mindanao",
      "CAR - Cordillera Administrative Region",
      "NCR - National Capital Region",
      "REGION I (Ilocos Region)",
      "REGION II (Cagayan Valley)",
      "REGION III (Central Luzon)",
      "REGION IV-A (Calabarzon)",
      "REGION IV-B (Mimaropa)",
      "REGION V (Bicol Region)",
      "REGION VI (Western Visayas)",
      "REGION VII (Central Visayas)",
      "REGION VIII (Eastern Visayas)",
      "REGION IX (Zamboanga Peninsula)",
      "REGION X (Northern Mindanao)",
      "REGION XI (Davao Region)",
      "REGION XII (Soccsksargen)",
      "REGION XIII (Caraga)"
    ]

  EventFields.insert
    "key": "province",
    "name": "Province",
    "order": 4,
    "type": "dropdown",
    "choices": [
      "Abra",
      "Agusan del Norte",
      "Agusan del Sur",
      "Aklan",
      "Albay",
      "Antique",
      "Apayao",
      "Aurora",
      "Basilan",
      "Bataan",
      "Batanes",
      "Batangas",
      "Benguet",
      "Biliran",
      "Bohol",
      "Bukidnon",
      "Bulacan",
      "Cagayan",
      "Camarines Norte",
      "Camarines Sur",
      "Camiguin",
      "Capiz",
      "Catanduanes",
      "Cavite",
      "Cebu",
      "Compostela Valley",
      "Cotabato",
      "Davao del Norte",
      "Davao del Sur",
      "Davao Oriental",
      "Dinagat Islands",
      "Eastern Samar",
      "Guimaras",
      "Ifugao",
      "Ilocos Norte",
      "Ilocos Sur",
      "Iloilo",
      "Isabela",
      "Kalinga",
      "La Union",
      "Laguna",
      "Lanao del Norte",
      "Lanao del Sur",
      "Leyte",
      "Maguindanao",
      "Marinduque",
      "Masbate",
      "Metro Manila",
      "Misamis Occidental",
      "Misamis Oriental",
      "Mountain Province",
      "Negros Occidental",
      "Negros Oriental",
      "Northern Samar",
      "Nueva Ecija",
      "Nueva Vizcaya",
      "Occidental Mindoro",
      "Oriental Mindoro",
      "Palawan",
      "Pampanga",
      "Pangasinan",
      "Quezon",
      "Quirino",
      "Rizal",
      "Romblon",
      "Samar",
      "Sarangani",
      "Siquijor",
      "Sorsogon",
      "South Cotabato",
      "Southern Leyte",
      "Sultan Kudarat",
      "Sulu",
      "Surigao del Norte",
      "Surigao del Sur",
      "Tarlac",
      "Tawi-Tawi",
      "Zambales",
      "Zamboanga del Norte",
      "Zamboanga del Sur",
      "Zamboanga Sibugay"
    ]

Meteor.startup ->
  return if Datastream.find().count() > 0

  # Load initial tweets on first start
  # loadDumbTweets()
  loadCSVTweets()

Meteor.startup ->
  return if EventFields.find().count() > 0

  loadEventFields()

