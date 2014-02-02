Template.exitsurvey.events =
  "submit form": (e, tmpl) ->
    e.preventDefault()

    results =
      comprehension: tmpl.find("textarea[name=comprehension]").value
      prepared: tmpl.find("textarea[name=prepared]").value
      bugs: tmpl.find("textarea[name=bugs]").value
      contact: tmpl.find("input[name=contact]").checked
      times: [
        tmpl.find("select[name=pickTime1]").value
        tmpl.find("select[name=pickTime2]").value
        tmpl.find("select[name=pickTime3]").value
      ]

    # TODO submit these
    console.log(results)
