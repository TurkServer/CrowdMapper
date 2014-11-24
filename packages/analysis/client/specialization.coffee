labels = {
  avgIndivEntropy: "Average Individual Entropy"
  groupEntropy: "Group Entropy"
  nominalSize: "Nominal Group Size"
  partialCreditScore: "Group Score"
}

Template.overviewSpecialization.helpers
  labels: _.map(labels, (v, k) -> { key: k, value: v } )

Template.overviewSpecialization.rendered = ->
  svg = @find("svg")

  leftMargin = 80
  bottomMargin = 50

  graphWidth = $(svg).width() - leftMargin
  graphHeight = $(svg).height() - bottomMargin

  colors = d3.scale.category10()
    .domain( [0...10] )

  graph = d3.select(svg).append("g")
    .attr("class", "graph")
    .attr("transform", "translate(#{leftMargin}, 0)")

  # TODO generalize this for transitions
  filteredData = @data
  xKey = null
  yKey = null
  displayOrdinal = false
  showBoxes = false

  # TODO allow selection of circle radius
  # radius = (g) -> 2 * Math.sqrt(g.partialCreditScore)
  radius = 5

  chart = d3.box()
    .whiskers(Util.iqrFun(1.5))
    .height(graphHeight)
    .showLabels(false)

  # x scale, to be set later with linear or ordinal
  x = null

  y = d3.scale.linear()
    .range([graphHeight, 0])

  xAxis = d3.svg.axis()
    .orient("bottom")

  xAxisGrid = d3.svg.axis()
    .orient("bottom")
    .tickSize(-graphHeight, 0, 0)
    .tickFormat("")

  yAxis = d3.svg.axis()
    .orient("left")
    .scale(y)

  yAxisGrid = d3.svg.axis()
    .orient("left")
    .scale(y)
    .tickSize(-graphWidth, 0, 0)
    .tickFormat("")

  d3.select(svg).append("g")
    .attr("class", "x axis")
    .attr("transform", "translate(#{leftMargin}, #{graphHeight})")
  .append("text")
    .attr("x", (graphWidth / 2))
    .attr("y", 30)
    .attr("dy", ".71em")

  d3.select(svg).append("g")
    .attr("class", "x grid")
    .attr("transform", "translate(#{leftMargin}, #{graphHeight})")

  d3.select(svg).append("g")
    .attr("class", "y axis")
    .attr("transform", "translate(#{leftMargin}, 0)")
  .append("text")
    .attr("transform", "rotate(-90)")
    .attr("x", -(graphHeight / 2))
    .attr("y", -55)
    .attr("dy", ".71em")

  d3.select(svg).append("g")
    .attr("class", "y grid")
    .attr("transform", "translate(#{leftMargin}, 0)")

  groupColor = (size) -> colors(Math.log(size) / Math.LN2)

  filterData = =>
    displayOrdinal = xKey is "nominalSize" and showBoxes

    if displayOrdinal
      filteredData = @data.filter( (d) -> d.nominalSize > 1 and d.treated )
    else
      filteredData = @data

  # Redraw X axis
  redrawX = ->
    xExtent = d3.extent(filteredData, (d) -> d[xKey])

    if displayOrdinal
      x = d3.scale.ordinal()
        .domain([2, 4, 8, 16, 32]) # TODO hack, compute sizes properly
        .rangeRoundBands([0, graphWidth], 0.6)

      chart.width(x.rangeBand())

    else
      xExtent[0] *= 0.9
      xExtent[1] *= 1.1

      x = d3.scale.linear()
        .domain(xExtent)
        .range([0, graphWidth])

    # Because x axis may have been replaced, update references
    xAxis.scale(x)
    xAxisGrid.scale(x)

    d3.select(".x.axis").call(xAxis)
    d3.select(".x.grid").call(xAxisGrid)
    d3.select(".x.axis > text").text(labels[xKey])

  redrawY = ->
    yExtent = d3.extent(filteredData, (d) -> d[yKey])
    yExtent[0] *= 0.9
    yExtent[1] *= 1.1

    y.domain(yExtent)

    d3.select(".y.axis").call(yAxis)
    d3.select(".y.grid").call(yAxisGrid)
    d3.select(".y.axis > text").text(labels[yKey])

  # Draw points or boxplots
  redrawData = ->
    if displayOrdinal
      graph.selectAll(".point").remove()
      # TODO hack; should not have to remove but box re-plotting is buggy
      graph.selectAll(".box").remove()

      # Draw box plots
      nested = d3.nest()
        .key( (d) -> d.nominalSize )
        .sortKeys(d3.ascending)
        .rollup( (leaves) -> leaves.map((d) -> d[yKey]) )
        .entries(filteredData)
        .map( (o) -> [o.key, o.values] )

      # Update boxplot domain from y axis
      chart.domain(y.domain())

      boxes = graph.selectAll(".box")
        .data(nested)

      boxes.enter().append("g")
        .attr("class", "box")

      boxes.attr("transform", (d) -> "translate(#{x(d[0])},0)")
        .call(chart)

    else
      graph.selectAll(".box").remove()

      # Draw points
      points = graph.selectAll(".point")
        .data(filteredData, (d) -> d._id)

      points.enter().append("circle")
        .attr("class", (g) -> "point " + g.treatments.join(" "))
        .attr("stroke", (g) -> groupColor(g.nominalSize) )
        .attr("fill", (g) -> if g.treated then groupColor(g.nominalSize) else "white" )
      .append("svg:title")
        .text((g) -> g._id)

      # Update display values
      points.attr("cx", (g) -> x(g[xKey]) #+ x.rangeBand() / 2
      )
      .attr("cy", (g) -> y(g[yKey]))
      .attr("r", radius )

  @setX = (key) ->
    xKey = key
    filterData()
    redrawX()
    redrawData()

  @setY = (key) ->
    yKey = key
    filterData()
    redrawY()
    redrawData()

  @setShowBoxes = (show) ->
    showBoxes = show
    filterData()
    redrawX() # May need to switch to ordinal mode
    redrawData()

  # Initial config
  xKey = "nominalSize"
  yKey = "groupEntropy"

  filterData()
  redrawX()
  redrawY()
  redrawData()

Template.overviewSpecialization.events
  "change input[name=xaxis]": (e, t) -> t.setX(e.target.value)
  "change input[name=yaxis]": (e, t) -> t.setY(e.target.value)
  "change input[name=boxplot]": (e, t) -> t.setShowBoxes(e.target.checked)

