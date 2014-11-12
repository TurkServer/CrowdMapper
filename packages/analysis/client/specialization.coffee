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

  xExtent = d3.extent(@data, (d) -> d.avgIndivEntropy)
  xExtent[0] *= 0.9
  xExtent[1] *= 1.1

  yExtent = d3.extent(@data, (d) -> d.groupEntropy)
  yExtent[0] *= 0.9
  yExtent[1] *= 1.1

  x = d3.scale.linear()
    .domain(xExtent)
    .range([0, graphWidth])

  y = d3.scale.linear()
    .domain(yExtent)
    .range([graphHeight, 0])

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

  d3.select(svg).append("g")
    .attr("class", "x axis")
    .attr("transform", "translate(#{leftMargin}, #{graphHeight})")
    .call(xAxis)
  .append("text")
    .attr("x", (graphWidth / 2))
    .attr("y", 30)
    .attr("dy", ".71em")
    .style("text-anchor", "middle")
    .text("Average Individual Entropy")

  d3.select(svg).append("g")
    .attr("class", "x grid")
    .attr("transform", "translate(#{leftMargin}, #{graphHeight})")
    .call(xAxisGrid)

  d3.select(svg).append("g")
    .attr("class", "y axis")
    .attr("transform", "translate(#{leftMargin}, 0)")
    .call(yAxis)
  .append("text")
    .attr("transform", "rotate(-90)")
    .attr("x", -(graphHeight / 2))
    .attr("y", -55)
    .attr("dy", ".71em")
    .style("text-anchor", "middle")
  .text("Group Entropy")

  d3.select(svg).append("g")
    .attr("class", "y grid")
    .attr("transform", "translate(#{leftMargin}, 0)")
    .call(yAxisGrid)

  groupColor = (size) -> colors(Math.log(size) / Math.LN2)

  graph.selectAll(".point")
    .data(@data, (d) -> d._id)
  .enter().append("circle")
    .attr("class", (g) -> "point " + g.treatments.join(" "))
    .attr("stroke", (g) -> groupColor(g.nominalSize) )
    .attr("fill", (g) -> if g.treated then groupColor(g.nominalSize) else "#ffffff" )
    .attr("cx", (g) -> x(g.avgIndivEntropy))
    .attr("cy", (g) -> y(g.groupEntropy))
    .attr("r", (g) -> 8 * Math.sqrt(g.totalEffort / g.personTime) )
  .append("svg:title")
    .text((g) -> g._id)
