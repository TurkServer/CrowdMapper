Util =
  # Overall classification of log actions
  logActionType: (entry) ->
    switch entry.action
      when "data-hide", "data-link" then "filter"
      when "event-create", "event-edit", "event-update", "event-save" then "classify"
      when "event-vote", "event-unvote", "event-unmap", "event-delete", "data-move", "data-unlink" then "verify"
      else ""

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

