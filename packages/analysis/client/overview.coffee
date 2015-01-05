Template.analysisOverview.helpers
  settings: {
    rowsPerPage: 100
    fields: [
      {
        key: "avgIndivEntropy"
        label: "mean indiv. entropy"
        fn: (v) -> v.toFixed(3)
        sortByValue: true
      },
      {
        key: "fullCreditScore"
        label: "0-1 score"
      },
      {
        key: "groupEntropy"
        label: "collective entropy"
        fn: (v) -> v.toFixed(3)
        sortByValue: true
      },
      {
        key: "nominalSize"
        label: "nominal size"
      },
      {
        key: "partialCreditScore"
        label: "partial score"
        fn: (v) -> v.toFixed(3)
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
        key: "treated"
        label: "treated"
      },
      {
        key: "wallTime"
        label: "wall time"
        fn: (v) -> v.toFixed(2)
        sortByValue: true
      },
      {
        key: "links"
        label: "links"
        tmpl: Template.analysisExpLinks
      }
    ]
  }

