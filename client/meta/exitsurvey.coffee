Template.exitsurvey.surveyTemplate = ->
  # TODO generalize this based on batch
  treatments = TurkServer.batch()?.treatments
  if _.indexOf(treatments, "recruiting") >= 0
    Template.tutorialSurvey
  else if _.indexOf(treatments, "parallel_worlds") >= 0
    Template.postTaskSurvey
  else
    Template.loadingSurvey

Template.tutorialSurvey.events
  "submit form": (e, tmpl) ->
    e.preventDefault()

    results =
      comprehension: tmpl.find("textarea[name=comprehension]").value
      prepared: tmpl.find("textarea[name=prepared]").value
      bugs: tmpl.find("textarea[name=bugs]").value

    panel =
      contact: tmpl.find("input[name=contact]").checked
      times: [
        tmpl.find("select[name=pickTime1]").value
        tmpl.find("select[name=pickTime2]").value
        tmpl.find("select[name=pickTime3]").value
      ]

    tmpl.find("button[type=submit]").disabled = true # Prevent multiple submissions

    TurkServer.submitExitSurvey(results, panel)

Template.postTaskSurvey.events
  "submit form": (e, tmpl) ->
    e.preventDefault()

    results = {}
    results.age = tmpl.find("input[name=age]").value
    results.gender = tmpl.find("select[name=gender]").value

    fields = [ "approach", "specialize", "teamwork", "workwith", "leadership", "misc" ]

    for field in fields
      results[field] = tmpl.find("textarea[name=#{field}]").value

    tmpl.find("button[type=submit]").disabled = true # Prevent multiple submissions

    TurkServer.submitExitSurvey(results)
