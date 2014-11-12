Template.overviewIndivPerformance.rendered = ->

  margin = {top: 30, right: 50, bottom: 70, left: 50}

  svg = @find("svg")

  accessor = (d) -> d.effort / d.time
  min = d3.min(@data, accessor)
  max = d3.max(@data, accessor)

  nest = d3.nest()
    .key( (d) -> d.groupSize )
    .sortKeys(d3.ascending)
    .rollup( (leaves) -> leaves.map(accessor) )
    .entries(@data)

  # Get this shit into the [0][1] format for rows
  data = nest.map( (o) -> [o.key, o.values] )

  width = $(svg).width() - margin.left - margin.right
  height = $(svg).height() - margin.top - margin.bottom

  chart = d3.box()
    .whiskers(Util.iqrFun(1.5))
    .height(height)
    .domain([min, max])
    .showLabels(true)

  # Switch svg over to d3 g element
  svg = d3.select(svg)
  .attr("class", "viz box")
  .append("g")
    .attr("transform", "translate(#{margin.left},#{margin.top})")

  # the x-axis
  x = d3.scale.ordinal()
    .domain([1, 2, 4, 8, 16, 32])
    .rangeRoundBands([0, width], 0.6, 0.3)

  xAxis = d3.svg.axis().scale(x).orient("bottom")

  # the y-axis
  y = d3.scale.linear()
    .domain([min, max])
    .range([height + margin.top, 0 + margin.top])

  yAxis = d3.svg.axis().scale(y).orient("left")

  # draw the boxplots
  svg.selectAll(".box")
    .data(data)
  .enter()
    .append("g")
    .attr("transform", (d) -> "translate(" + x(d[0]) + "," + margin.top + ")")
    .call chart.width(x.rangeBand())

  # draw y axis
  svg.append("g")
    .attr("class", "y axis")
    .call(yAxis)
  .append("text")
    .attr("transform", "rotate(-90)")
    .attr("y", 6)
    .attr("dy", ".71em")
    .style("text-anchor", "end")
    .text("Normalized Effort")

  # draw x axis
  # text label for the x axis
  svg.append("g")
    .attr("class", "x axis")
    .attr("transform", "translate(0," + (height + margin.top + 10) + ")")
    .call(xAxis)
  .append("text")
    .attr("x", (width / 2))
    .attr("y", 10)
    .attr("dy", ".71em")
    .style("text-anchor", "middle")
    .text("Group Size")
