height = 700
leftMargin = 80
bottomMargin = 50

Template.overviewGroupSlices.helpers({
  height: height
  leftMargin: leftMargin
  bottomOffset: height - bottomMargin
  points: -> Analysis.Worlds.find({treated: true})
  treatments: -> this.treatments.join(" ")
  xLabelPosition: 450
  yLabelPosition: (height - bottomMargin) / 2
  settingOf: (key) ->
    val = Template.instance().settings.get(key)
    return val.toFixed(2) if $.isNumeric(val)
    return val
})

Template.overviewGroupSlices.created = ->
  @settings = new ReactiveDict

Template.overviewGroupSlices.rendered = ->
  @slider = this.$(".slider").slider({
    min: 0
    step: 0.01
    slide: (event, ui) =>
      # This updates faster than the reactive bits
      this.$(".slider-immediate").text(ui.value)
    change: (event, ui) =>
      this.$(".slider-immediate").text(ui.value)
      @settings.set("sliceValue", ui.value)
  })

  @setField = (field, value, label) ->
    @settings.set(field, value)
    # Update y axis label if necessary
    if field is "groupScoring" then @settings.set("yLabel", label)

  # default settings - change in template; fields must match here
  for field in [ "groupScoring", "xScale", "groupComparator" ]
    $input = @$("input[name=#{field}]:checked")
    value = $input.val()
    label = $input.closest("label").text().trim()
    @setField(field, value, label)

  svg = @find("svg")

  graphWidth = $(svg).width() - leftMargin
  graphHeight = $(svg).height() - bottomMargin

  x = null

  y = d3.scale.linear()
  .range([graphHeight, 0])

  # Median line draw-er.
  line = d3.svg.line()
  .x((d) -> x(d.key))
  .y((d) -> y(d.values))

  xAxis = d3.svg.axis()
  .orient("bottom")

  xGrid = d3.svg.axis()
  .orient("bottom")
  .tickSize(-graphHeight, 0, 0)
  .tickFormat("")

  yAxis = d3.svg.axis()
  .orient("left")
  .scale(y)

  yGrid = d3.svg.axis()
  .orient("left")
  .scale(y)
  .tickSize(-graphWidth, 0, 0)
  .tickFormat("")

  transDuration = 600

  # Set slider value appropriately and a default slice value.
  this.autorun =>
    xField = Util.fieldAbbr[@settings.get("groupComparator")]

    data = d3.select(svg).selectAll(".point").data()

    # min-max is largest value for which all groups have this field
    [sliceVal, sliceMax] = d3.extent data, (g) ->
      g.progress[g.progress.length - 1][xField]

    # Special case: don't let wallTime go over 1
    sliceMax = Math.min(sliceMax, 1) if xField is "wt"

    # set new slice value, which will update the function below.
    @slider.slider "option",
      max: sliceMax
      value: sliceVal # Propagates through the callback

    @settings.set("sliceMax", sliceMax)

    return

  # Display x scale appropriately.
  this.autorun =>
    xScale = @settings.get("xScale")

    if xScale is "linear"
      x = d3.scale.linear()
        .domain([0, 33])
        .range([0, graphWidth])
    else
      x = d3.scale.log()
        .base(2)
        .domain([0.5, 40])
        .range([0, graphWidth])

    xAxis.tickValues([1, 2, 4, 8, 16, 32])
    xAxis.tickFormat(x.tickFormat(6, "2d"))
    xAxis.scale(x)
    xGrid.scale(x)

    # Transition x axis and grid.
    d3.select(svg)
    .transition()
    .duration(transDuration)
    .each ->

      d3.select(this).selectAll(".x.axis")
      .transition().call(xAxis)
      d3.select(this).selectAll(".x.grid")
      .transition().call(xGrid)

  # Update axes and transition the points.
  this.autorun =>
    xScale = @settings.get("xScale") # redraw if this changes.

    xField = Util.fieldAbbr[@settings.get("groupComparator")]
    yField = Util.fieldAbbr[@settings.get("groupScoring")]

    sliceVal = @settings.get("sliceValue")

    points = d3.select(svg).selectAll(".point")
    pointData = points.data()

    # Compute new interpolated values in-place while simultaneously returning them.
    yMax = d3.max pointData, (g) ->
      g.interp = Util.interpolateArray(g.progress, xField, yField, sliceVal)

    # Run linear regression on points that exist
    validPoints = pointData.filter (g) -> g.interp?

    regData = validPoints.map (g) ->
      [ (if xScale is "log" then Math.log(g.nominalSize)/Math.LN2 else g.nominalSize), g.interp ]

    # Run simple linear regression
    reg = ss.linear_regression().data(regData)
    regLine = reg.line()
    r2 = ss.r_squared(regData, regLine)

    indepVarText = if xScale is "log" then "log2(groupSize)" else "groupSize"

    regText = """#{@settings.get("groupScoring")} = #{reg.m().toFixed(2)} x #{indepVarText} + #{reg.b().toFixed(2)}, R^2 = #{r2.toFixed(4)}"""

    # Shared transition.
    d3.select(svg)
    .transition()
    .duration(transDuration)
    .each ->
      # Transition y axis
      y.domain([0, yMax * 1.1])

      d3.select(this).selectAll(".y.axis")
      .transition().call(yAxis)

      d3.select(this).selectAll(".y.grid")
      .transition().call(yGrid)

      # Update point values
      points.transition().attr({
        cx: (g) -> x(g.nominalSize)
        cy: (g) -> y(g.interp || 0)
      })

      # Transition median line, using only values that exist
      medians = d3.nest()
      .key((g) -> g.nominalSize ).sortKeys( (a, b) -> a - b)
      .rollup((leaves) -> d3.median(leaves, (g) -> g.interp) )
      .entries( validPoints )

      d3.select(this).selectAll(".line.median").datum(medians)
      .transition().attr("d", line)

      # Transition regression line
      if xScale is "log"
        y1 = y(regLine( Math.log(x.domain()[0]) / Math.LN2 ))
        y2 = y(regLine( Math.log(x.domain()[1]) / Math.LN2 ))
      else
        y1 = y(regLine(x.domain()[0]))
        y2 = y(regLine(x.domain()[1]))

      d3.select(this).selectAll(".line.regression")
      .transition().attr({
          "x1": x.range()[0]
          "y1": y1
          "x2": x.range()[1]
          "y2": y2
        })

      d3.select(this).selectAll("text.regression").text(regText)

Template.overviewGroupSlices.events
  "change input": (e, t) ->
    t.setField(e.target.name, e.target.value, $(e.target).closest("label").text().trim())

Template.groupSlicePoint.rendered = ->
  # Bind the meteor data to d3's datum.
  point = d3.select(this.firstNode)
  point.datum(@data)


