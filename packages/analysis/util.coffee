# Define analysis global for export
Analysis = {}

bisectors = {}

Util =
  # Overall classification of log actions
  logActionType: (entry) ->
    switch entry.action
      when "data-hide", "data-link" then "filter"
      when "event-create", "event-edit", "event-update", "event-save" then "classify"
      when "event-vote", "event-unvote", "event-unmap", "event-delete", "data-move", "data-unlink" then "verify"
      else ""

  typeFields: [ "filter", "classify", "verify", "chat", "" ]

  # Convenience function for binning log or chat actions
  actionType: (item) ->
    if item.timestamp? then "chat" else Util.logActionType(item)

  weightOf: (item, weights) ->
    # Chat entry
    return weights.chat if item.timestamp?
    # Log entry
    return weights[item.action] || 0

  # Returns a function to compute the interquartile range.
  iqrFun: (k) ->
    (d, i) ->
      q1 = d.quartiles[0]
      q3 = d.quartiles[2]
      iqr = (q3 - q1) * k
      i = -1
      j = d.length
      while (d[++i] < q1 - iqr)
        null
      while (d[--j] > q3 + iqr)
        null
      return [ i, j ]

  # Abbreviations used in progress array
  fieldAbbr:
    partialCreditScore: "ps"
    fullCreditScore: "ss"
    totalEffort: "ef"
    wallTime: "wt"
    personTime: "mt"

  # Memoize bisectors so they aren't constructed each time.
  getBisector: (key) ->
    return bisectors[key] ?= d3.bisector( (d) -> d[key] )

  # compute a linearly interpolated value for a field in a progress array.
  interpolateArray: (progress, xField, yField, xVal) ->
    return if progress[progress.length - 1][xField] < xVal
    bisector = Util.getBisector(xField)

    i = bisector.right(progress, xVal)

    lower = progress[i - 1] || progress[0]
    upper = progress[i]

    l = (xVal - lower[xField]) / (upper[xField] - lower[xField])
    return l * upper[yField] + (1-l) * lower[yField]
