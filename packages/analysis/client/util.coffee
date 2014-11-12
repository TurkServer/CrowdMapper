Util =
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
