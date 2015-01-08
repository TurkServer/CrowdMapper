Template.overview.events
  "click .cm-analysis": (e) ->
    method = $(e.target).data("method")

    dialog = bootbox.dialog
      closeButton: false
      message: "<h3>Working...</h3>"

    Meteor.call method, (err, res) ->
      dialog.modal("hide")
      if err
        bootbox.alert(err)
      else
        bootbox.alert("done")

Template.analysisExpLinks.helpers
  # Get the groupId associated with an analysis.world or analysis.person.
  id: -> @instanceId || @_id

Template.overviewExperiments.helpers
  settings: {
    collection: Analysis.Worlds
    rowsPerPage: 100
    fields: [
      {
        key: "nominalSize"
        label: "nominal size"
      },
      {
        key: "wallTime"
        label: "wall time"
        fn: (v) -> v.toFixed(2)
        sortByValue: true
      },
      {
        key: "personTime"
        label: "person-time"
        fn: (v) -> v.toFixed(2)
        sortByValue: true
      },
      {
        key: "totalEffort"
        label: "effort-time"
        fn: (v) -> v.toFixed(2)
        sortByValue: true
      },
      {
        key: "personEffort"
        label: "effort/person"
        fn: (v, o) ->
          # Return a number so value is properly sorted
          +(o.totalEffort / o.personTime).toFixed(2)
      },
      {
        key: "treated"
        label: "valid treatment"
      },
      {
        key: "partialCreditScore"
        label: "partial score"
        fn: (v) -> v.toFixed(3)
        sortByValue: true
      },
      {
        key: "fullCreditScore"
        label: "0-1 score"
      },
      {
        key: "avgIndivEntropy"
        label: "mean indiv. entropy"
        fn: (v) -> v.toFixed(3)
        sortByValue: true
      },
      {
        key: "groupEntropy"
        label: "collective entropy"
        fn: (v) -> v.toFixed(3)
        sortByValue: true
      },
      {
        key: "links"
        label: "links"
        tmpl: Template.analysisExpLinks
      }
    ]
  }

Template.overviewPeople.helpers
  settings: {
    collection: Analysis.People
    rowsPerPage: 100
    fields: [
      {
        key: "groupSize"
        label: "group size"
      },
      {
        key: "time"
        label: "active time"
        fn: (v) -> v.toFixed(2)
        sortByValue: true
      },
      {
        key: "effort"
        label: "effort-time"
        fn: (v) -> v.toFixed(2)
        sortByValue: true
      },
      {
        key: "treated"
        label: "valid treatment"
      },
      {
        key: "links"
        label: "links"
        tmpl: Template.analysisExpLinks
      }

    ]
  }

Template.overviewStats.helpers
  actionArray: -> ({action: k, time: v} for k, v of this)
  settings: {
    rowsPerPage: 50
    fields: [
      {
        key: "action"
        label: "action"
      },
      {
        key: "time"
        label: "mean time since previous action (s)"
        fn: (v) -> (v / 1000).toFixed(2)
        sortByValue: true
      }
    ]
  }

Template.sizeLegend.helpers
  color: Util.groupColor
