skipEventSize = 20

computeGraph = (occurrences, filter) ->
  occurrences = _.filter(occurrences, (o) -> o.length <= skipEventSize)

  # compute number of occurrences for each tweet
  nodes = d3.nest()
  .key(Object)
  .rollup( (leaves) -> leaves.length )
  .entries($.map(occurrences, Object))

  # Only consider tweets that were tagged at least once
  nodes = _.filter(nodes, (e) -> e.values > 1) if filter

  # Create a map of nodes for the next step (may be helpful later too)
  indices = {}
  for obj, i in nodes
    indices[obj.key] = i

  console.log "#{nodes.length} nodes"

  # Compute co-occurrences for each pair

  # Create a temporary 2-level associative array, indexing higher numbers first
  linkMap = {}

  for arr in occurrences

    for x, i in arr
      continue unless indices[x]

      j = i+1

      while j < arr.length
        y = arr[j]
        j++
        continue unless indices[y]

        [first, second] = if parseInt(x) > parseInt(y) then [x, y] else [y, x]

        linkMap[first] ?= {}
        linkMap[first][second] ?= { count: 0 }
        linkMap[first][second].count++

  links = []

  for k1, map of linkMap
    for k2, val of map
      links.push
        source: indices[k1]
        target: indices[k2]
        value: val.count

  console.log "#{links.length} edges"

  return [nodes, links]

minNodeRadius = 3
minCharge = -15

Template.overviewTagging.rendered = ->
  tmpl = this

  occurrences = this.data.occurrences
  tweetText = this.data.tweetText

  console.log "#{occurrences.length} events"

  svg = @find("svg")
  width = $(svg).width()
  height = $(svg).height()

  gEdges = d3.select(svg).append("g")
  gNodes = d3.select(svg).append("g")

  strengthScale = d3.scale.pow().exponent(3)

  force = d3.layout.force()
  .size([width, height])
  # Bigger nodes should repel harder, but not too much harder...
  .charge( (d) -> minCharge * d.values )
  .linkDistance(15)

  @redrawGraph = (filterNodes) ->
    [nodes, links] = computeGraph(occurrences, filterNodes)

    maxStr = d3.max(nodes, (d) -> d.values)

    # The co-occurrence strength needs to be nonlinear
    # and rapidly increasing with for smaller values
    force.linkStrength( (e) -> 1 - strengthScale(1 - e.value / maxStr) )
    .nodes(nodes)
    .links(links)

    linkEls = gEdges.selectAll(".link")
    .data(links, (l) -> "#{l.source},#{l.target}" )

    linkEls.enter().append("line")
    .attr("class", "link")
    .style("stroke-width", (d) -> Math.sqrt(d.value) )

    linkEls.exit().remove()

    nodeEls = gNodes.selectAll(".node")
    .data(nodes, (n) -> n.key)

    nodeEls.enter().append("circle")
    .attr("class": "node")
    .attr("r", (d) -> minNodeRadius * Math.sqrt(d.values) )
    # .style("fill", function(d) { return color(d.group); })
    .call(force.drag)
    .append("title")
    .text( (d) -> "#{d.key} #{tweetText[parseInt(d.key)]}" )

    nodeEls.exit().remove()

    tmpl.link = linkEls
    tmpl.node = nodeEls

    force.start()

  # Redraw events
  force.on "tick", ->
    tmpl.link
    .attr("x1", (d) -> d.source.x )
    .attr("y1", (d) -> d.source.y )
    .attr("x2", (d) -> d.target.x )
    .attr("y2", (d) -> d.target.y )
    tmpl.node
    .attr("cx", (d) -> d.x)
    .attr("cy", (d) -> d.y)

  @redrawGraph(false) # With checked box

Template.overviewTagging.events
  "change input[type=checkbox]": (e, t) ->
    t.redrawGraph(e.target.checked)
