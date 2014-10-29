# Abbreviations used in array
abbrv =
  partialCreditScore: "ps"
  fullCreditScore: "ss"
  totalEffort: "ef"
  wallTime: "wt"
  personTime: "mt"

Template.overviewGroupPerformance.rendered = ->
  svg = @find("svg")

  leftMargin = 80
  bottomMargin = 30

  graphWidth = $(svg).width() - leftMargin
  graphHeight = $(svg).height() - bottomMargin

  graph = d3.select(svg).append("g")
    .attr("class", "graph")
    .attr("transform", "translate(#{leftMargin}, 0)")

  colors = d3.scale.category10()
    .domain( [0...10] )

  x = d3.scale.linear()
    .domain([0, 33]) # Need an initial X domain for the first y transition
    .range([0, graphWidth])

  y = d3.scale.linear()
    .range([graphHeight, 0])

  line = d3.svg.line()
    .x((d) -> x(d.key))
    .y((d) -> y(d.values))

  lineProgress = d3.svg.line()

  xAxis = d3.svg.axis()
    .orient("bottom")
    .scale(x)

  xAxisGrid = d3.svg.axis()
    .orient("bottom")
    .scale(x)
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

  zoom = d3.behavior.zoom()
    .x(x)
    .scaleExtent([1, 20])

  d3.select(svg).append("g")
    .attr("class", "x axis")
    .attr("transform", "translate(#{leftMargin}, #{graphHeight})")

  d3.select(svg).append("g")
    .attr("class", "x grid")
    .attr("transform", "translate(#{leftMargin}, #{graphHeight})")

  d3.select(svg).append("g")
    .attr("class", "y axis")
    .attr("transform", "translate(#{leftMargin}, 0)")

  d3.select(svg).append("g")
    .attr("class", "y grid")
    .attr("transform", "translate(#{leftMargin}, 0)")

  groupColor = (g) -> colors(Math.log(g.nominalSize) / Math.LN2)

  # Draw progress lines
  graph.selectAll("path.progress")
    .data(@data, (g) -> g._id)
  .enter().append("path")
    .attr("class", (g) -> "progress line " + g.treatments.join(" "))
    .style("stroke", groupColor )

  # Draw final points
  graph.selectAll(".point")
    .data(@data, (g) -> g._id)
  .enter().append("circle")
    .attr("class", (g) -> "point " + g.treatments.join(" ") )
    .attr("fill", groupColor )
    .attr("cx", (g) -> x(g.nominalSize))
    .attr("r", 4)
  .append("svg:title")
    .text((g) -> g._id)

  medianLine = graph.append("path")
    .attr("class", "line")

  xField = null
  xFieldAbbr = null
  yField = null
  yFieldAbbr = null
  showProgress = false

  tdur = 600

  # y axis values
  @setScoring = (field) =>
    yField = field
    yFieldAbbr = abbrv[yField]

    # Transition y axis
    maxScore = d3.max(@data, (g) -> g[yField])

    y.domain([0, maxScore * 1.1])

    d3.select(svg).selectAll(".y.axis")
      .transition().duration(tdur)
      .call(yAxis)

    d3.select(svg).selectAll(".y.grid")
      .transition().duration(tdur)
      .call(yAxisGrid)

    @transitionLines()
    @transitionPoints()

  # x axis values
  @setComparator = (field) =>
    if field?
      xField = field
      xFieldAbbr = abbrv[xField]

    maxVal = d3.max(@data, (g) -> g[xField])

    # Reset zoom
    zoom.translate([0, 0]).scale(1)

    # Transition x axis
    x.domain([0, maxVal * 1.1])
    zoom.x(x)

    if xField is "nominalSize"
      xAxis.tickValues( [1, 2, 4, 8, 16, 32] )
    else
      xAxis.tickValues(null) # Generate default tick values

    @transitionXAxis()

    # Show median only for nominal group size
    @transitionMedian()
    @transitionLines()
    @transitionPoints()

  # Zoom does all the same transitions as x
  zoom.on "zoom", =>
    # TODO ugly hack! Reuse d3 selections properly.
    tdur = 0

    @transitionXAxis()

    # Show median only for nominal group size
    @transitionMedian()
    @transitionLines()
    @transitionPoints()

    tdur = 600

  d3.select(svg).call(zoom)

  @setShowProgress = (show) =>
    showProgress = show
    @transitionLines()

  @transitionXAxis = () ->
    d3.select(svg).selectAll(".x.axis")
      .transition().duration(tdur)
      .call(xAxis)

    d3.select(svg).selectAll(".x.grid")
      .transition().duration(tdur)
      .call(xAxisGrid)

  @transitionMedian = () =>
    unless xField is "nominalSize"
      medianLine.style("opacity", 0)
      return

    medianLine.style("opacity", 1)

    # Create a nest for computing the median
    medians = d3.nest()
      .key((g) -> g.nominalSize ).sortKeys( (a, b) -> a - b)
      .rollup((leaves) -> d3.median(leaves, (g) -> g[yField]) )
      .entries(@data)

    medianLine.datum(medians)
      .transition().duration(tdur).attr("d", line)

  @transitionLines = () =>
    lines = graph.selectAll("path.progress")

    unless showProgress and xFieldAbbr?
      lines.style("opacity", 0)
      return

    lines.style("opacity", 1)

    # Update accessor and redraw paths
    lineProgress.x( (d) -> x(d[xFieldAbbr]) )
    lineProgress.y( (d) -> y(d[yFieldAbbr]) )

    lines.transition().duration(tdur).attr("d", (g) -> lineProgress(g.progress))

  @transitionPoints = () =>
    graph.selectAll(".point")
      .transition().duration(tdur)
      .attr("cy", (g) -> y(g[yField]))
      .attr("cx", (g) -> x(g[xField]))

  # Initial draw - default settings
  @setScoring("partialCreditScore")
  @setComparator("nominalSize")

Template.overviewGroupPerformance.events
  "change input[name=progress]": (e, t) ->
    t.setShowProgress(e.target.checked)
  "change input[name=groupScoring]": (e, t) ->
    t.setScoring(e.target.value)
  "change input[name=groupComparator]": (e, t) ->
    t.setComparator(e.target.value)
