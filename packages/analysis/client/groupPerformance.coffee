# Abbreviations used in array
abbrv =
  partialCreditScore: "ps"
  fullCreditScore: "ss"
  totalEffort: "ef"
  wallTime: "wt"
  personTime: "mt"

Template.overviewGroupPerformance.rendered = ->
  # Sort treated data for averaging later
  nested = d3.nest()
    .key( (d) -> d.nominalSize )
    .sortKeys(d3.ascending)
    .entries(@data.filter( (d) -> d.treated ))

  svg = @find("svg")

  leftMargin = 80
  bottomMargin = 50

  graphWidth = $(svg).width() - leftMargin
  graphHeight = $(svg).height() - bottomMargin

  graph = d3.select(svg).append("g")
    .attr("class", "graph")
    .attr("transform", "translate(#{leftMargin}, 0)")

  colors = d3.scale.category10()
    .domain( [0...10] )

  # Color the legend
  # TODO horrible hack, ugh
  legend = @find(".legend")
  d3.select(legend).selectAll("div")
  .each ->
    size = Math.log($(this).data("legend")) / Math.LN2
    d3.select(this).style("background", colors(size))

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
    .y(y)
    .scaleExtent([1, 20])

  xg = d3.select(svg).append("g")
    .attr("class", "x axis")
    .attr("transform", "translate(#{leftMargin}, #{graphHeight})")

  xLabel = xg.append("text")
    .attr("x", (graphWidth / 2))
    .attr("y", 25)
    .attr("dy", ".71em")
    .style("text-anchor", "middle")

  d3.select(svg).append("g")
    .attr("class", "x grid")
    .attr("transform", "translate(#{leftMargin}, #{graphHeight})")

  yg = d3.select(svg).append("g")
    .attr("class", "y axis")
    .attr("transform", "translate(#{leftMargin}, 0)")

  yLabel = yg.append("text")
    .attr("transform", "rotate(-90)")
    .attr("x", -(graphHeight / 2))
    .attr("y", -50)
    .attr("dy", ".71em")
    .style("text-anchor", "middle")

  d3.select(svg).append("g")
    .attr("class", "y grid")
    .attr("transform", "translate(#{leftMargin}, 0)")

  groupColor = (size) -> colors(Math.log(size) / Math.LN2)

  gBox = graph.append("g")
    .attr("class", "boxplots")

  # Draw progress lines
  graph.selectAll("path.progress")
    .data(@data.filter( (d) -> !(d.pseudo or d.synthetic)), (g) -> g._id)
  .enter().append("path")
    .attr("class", (g) ->
      cls = "progress line " + g.treatments.join(" ")
      cls += " untreated" unless g.treated
      return cls
    )
    .style("stroke", (g) -> groupColor(g.nominalSize) )

  graph.selectAll("path.average")
    .data(nested, (g) -> g.key)
  .enter().append("path")
    .attr("class", (g) -> "line average group_" + g.key)
    .style("stroke", (g) -> groupColor(g.key) )

  graph.selectAll("path.pseudo")
    .data(@data.filter( (d) -> d.pseudo ), (g) -> g._id )
  .enter().append("path")
    .attr("class", (g) -> "line pseudo group_" + g.nominalSize)
    .style("stroke", (g) -> groupColor(g.nominalSize) )

  # Draw final points
  graph.selectAll(".point")
    .data(@data.filter( (d) -> !(d.pseudo or d.synthetic)), (g) -> g._id)
  .enter().append("circle")
    .attr("class", (g) -> "point " + g.treatments.join(" "))
    .attr("stroke", (g) -> groupColor(g.nominalSize) )
    .attr("fill", (g) -> if g.treated then groupColor(g.nominalSize) else "#ffffff" )
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

  # Checkbox settings
  showProgress = false
  showAverages = false
  showPseudos = false

  tdur = 600

  # y axis values
  @setScoring = (field, label) =>
    yField = field
    yFieldAbbr = abbrv[yField]

    yLabel.text(label)

    # Transition y axis
    maxScore = d3.max(@data, (g) -> g[yField])

    y.domain([0, maxScore * 1.1])

    @transitionYAxis()

    @transitionLines()
    @transitionPoints()


  # x axis values
  @setComparator = (field, label) =>
    if field?
      xField = field
      xFieldAbbr = abbrv[xField]

    xLabel.text(label)

    maxVal = d3.max(@data, (g) -> g[xField])
    maxScore = d3.max(@data, (g) -> g[yField])

    # Reset zoom, both x and y
    zoom.translate([0, 0]).scale(1)

    x.domain([0, maxVal * 1.1])
    y.domain([0, maxScore * 1.1])
    zoom.x(x)
    zoom.y(y)

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
    # Might require update to D3 3.4 or later for better transition support.
    tdur = 0

    @transitionXAxis()
    @transitionYAxis()

    # Show median only for nominal group size
    @transitionMedian()
    @transitionLines()
    @transitionPoints()

    tdur = 600

  d3.select(svg).call(zoom)

  @setShowProgress = (show) =>
    showProgress = show
    @transitionLines()

  @setShowAverages = (show) =>
    showAverages = show
    @transitionLines()

  @setShowPseudo = (show) =>
    showPseudos = show
    @transitionLines()

  @setShowSynthetic = (show) =>
    unless show
      gBox.selectAll(".box").remove()
      return

    # Synthetic box plots
    box = d3.box()
      .whiskers(Util.iqrFun(1.5))
      .height(graphHeight)
      .showLabels(false)

    # Nest data for boxplots
    # TODO this probably doesn't need to be re-nested each time
    synthetic = d3.nest()
      .key( (d) -> d.personTime )
      .sortKeys(d3.ascending)
      .rollup( (leaves) -> leaves.map( (d) -> d[yField] ) )
      .entries(@data.filter (d) -> d.synthetic)
      .map( (o) -> [o.key, o.values] )

    boxWidth = 12

    box.domain(y.domain()).width(boxWidth)

    boxes = gBox.selectAll(".box")
      .data(synthetic)

    boxes.enter().append("g")
      .attr("class", "box")

    boxes.attr("transform", (d) -> "translate(#{x(d[0]) - boxWidth/2},0)")
      .call(box)

  @transitionXAxis = () ->
    d3.select(svg).selectAll(".x.axis")
      .transition().duration(tdur)
      .call(xAxis)

    d3.select(svg).selectAll(".x.grid")
      .transition().duration(tdur)
      .call(xAxisGrid)

  @transitionYAxis = () =>
    d3.select(svg).selectAll(".y.axis")
      .transition().duration(tdur)
      .call(yAxis)

    d3.select(svg).selectAll(".y.grid")
      .transition().duration(tdur)
      .call(yAxisGrid)

  @transitionMedian = () =>
    unless xField is "nominalSize"
      medianLine.style("opacity", 0)
      return

    medianLine.style("opacity", 1)

    # Create a nest for computing the median
    medians = d3.nest()
      .key((g) -> g.nominalSize ).sortKeys( (a, b) -> a - b)
      .rollup((leaves) -> d3.median(leaves, (g) -> g[yField]) )
      .entries(@data.filter (d) -> d.treated )

    medianLine.datum(medians)
      .transition().duration(tdur).attr("d", line)

  @transitionLines = () =>
    lines = graph.selectAll("path.progress")
    averages = graph.selectAll("path.average")
    pseudos = graph.selectAll("path.pseudo")

    unless showProgress and xFieldAbbr?
      lines.style("opacity", 0)
      averages.style("opacity", 0)
      pseudos.style("opacity", 0)
      return

    # Update accessor and redraw paths
    lineProgress.x( (d) -> x(d[xFieldAbbr]) )
    lineProgress.y( (d) -> y(d[yFieldAbbr]) )

    if showAverages
      lines.style("opacity", 0)
      averages.style("opacity", 1)

      # Compute new averages using current fields.
      # Average the interpolation every 1/10 of whatever is currently being displayed.
      computeAverages = (grouping) ->
        groups = grouping.values

        bisector = d3.bisector( (d) -> d[xFieldAbbr] )
        result = []

        i = 0
        while 1
          sum = 0
          counted = 0
          for group in groups
            progress = group.progress
            # Average only over groups that have gotten up to this value
            continue if progress[progress.length - 1][xFieldAbbr] < i
            idx = bisector.right(progress, i)

            lower = progress[idx - 1] || progress[0]
            upper = progress[idx]

            frac = (i - lower[xFieldAbbr]) / (upper[xFieldAbbr] - lower[xFieldAbbr])
            sum += frac * upper[yFieldAbbr] + (1-frac) * lower[yFieldAbbr]
            counted++

          # TODO better control over what is being averaged
          break if (counted < groups.length - 1) or (counted < groups.length and grouping.key > 3)

          bit = {}
          bit[xFieldAbbr] = i
          bit[yFieldAbbr] = sum / counted

          result.push(bit)

          i += 0.1

        return lineProgress(result)

      averages.transition().duration(tdur).attr("d", computeAverages)

    else
      averages.style("opacity", 0)
      lines.style("opacity", 1)

      lines.transition().duration(tdur).attr("d", (g) -> lineProgress(g.progress))

    if showPseudos
      pseudos.style("opacity", 1)
      pseudos.transition().duration(tdur).attr("d", (g) -> lineProgress(g.progress))
    else
      pseudos.style("opacity", 0)

  @transitionPoints = () =>
    graph.selectAll(".point")
      .transition().duration(tdur)
      .attr("cy", (g) -> y(g[yField]))
      .attr("cx", (g) -> x(g[xField]))

  # Initial draw - default settings
  # TODO set initial labels
  @setScoring("partialCreditScore")
  @setComparator("nominalSize")

Template.overviewGroupPerformance.events
  "change input[name=progress]": (e, t) ->
    t.setShowProgress(e.target.checked)
  "change input[name=averages]": (e, t) ->
    t.setShowAverages(e.target.checked)
  "change input[name=pseudo]": (e, t) ->
    t.setShowPseudo(e.target.checked)
  "change input[name=synthetic]": (e, t) ->
    t.setShowSynthetic(e.target.checked)
  "change input[name=groupScoring]": (e, t) ->
    label = $(e.target).closest("label").text().trim()
    t.setScoring(e.target.value, label)
  "change input[name=groupComparator]": (e, t) ->
    label = $(e.target).closest("label").text().trim()
    t.setComparator(e.target.value, label)
