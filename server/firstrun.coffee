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
  return if EventFields.find().count() > 0

  loadEventFields()

# Set up treatments
Meteor.startup ->
  Treatments.upsert {name: "tutorial"},
    $set:
      tutorial: "pre_task"
      payment: 1.00

  Treatments.upsert {name: "recruiting"},
    $set:
      tutorial: "recruiting"
      payment: 1.00

  Treatments.upsert {name: "parallel_worlds"},
    $set:
      wage: 6.00
      bonus: 9.00
