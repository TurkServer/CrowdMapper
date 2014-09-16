preprocess = (data) ->
  # This won't be necessary other than for the pilot data.
  logs = data.logs

  move_reclassify = 0
  unlink_reclassify = 0

  i = 0
  while i < logs.length
    if logs[i].action is "data-unlink"
      j = Math.max(i - 5, 0)
      while ++j < logs.length and (j - i) < 5
        # data-unlink followed by data-link (in the near future) should be
        # reclassified as a "data-move" action
        if logs[j].action is "data-link" and logs[j].dataId is logs[i].dataId
          move_reclassify++

          logs[i].action = "data-move"
          logs[i].fromEventId = logs[i].eventId
          logs[i].toEventId = logs[j].eventId

          delete logs[i].eventId
          logs.splice(j, 1)

          # If we delete a number *before* i, then don't increment
          i-- if j < i
          break
        # Also splice data-hide actions caused by unlinking
        else if logs[j].action is "data-hide" and logs[j].dataId is logs[i].dataId
          unlink_reclassify++

          logs.splice(j, 1)
          i-- if j < i
          break
    i++

  console.log "Moves re-classified: #{move_reclassify}", "Unlinks re-classified: #{unlink_reclassify}"

tags = /[~@#]/

#  console.log @data.instance
#  console.log "users", @data.users
#  console.log "logs", @data.logs
#  console.log "chat", @data.chat

# What overall type of action is this?
entryActionType = (entry) ->
  switch entry.action
    when "data-hide", "data-link" then "filter"
    when "event-create", "event-edit", "event-update", "event-save" then "classify"
    when "event-vote", "event-unvote", "event-unmap", "event-delete", "data-move", "data-unlink" then "verify"
    else ""

vizType = (entry) ->
  switch entryActionType(entry)
    when "filter", "verify" then  0
    else 1

entryActionField = (entry) ->
  field = null
  for k, v of entry?.fields
    field = k
    break
  return field

logEntryClass = (entry) ->
  field = entryActionField(entry) || ""
  return "action #{entry.action || entry._meta} #{field}"

chatMsgClass = (msg) ->
  if msg.text.match(tags)
    tagged = "tagged"
  return "chat #{tagged}"

# All actions in the given time range that are not meta actions
filterLogs = (logs, extent) ->
  _.filter logs, (entry) ->
    extent[0] < entry._timestamp < extent[1] and not entry._meta?

filterChat = (chat, extent) ->
  _.filter chat, (entry) ->
    extent[0] < entry.timestamp < extent[1]

vizPointWidth = 5


Session.setDefault("vizType", "time")

Template.viz.events
  "click nav a": (e, t) ->
    e.preventDefault()
    target = $(e.target).data("target")

    Session.set("vizType", target)

  "change input[name=pieLayout]": (e, t) ->
    t.layout = e.target.value
    t.reposition()

Template.viz.rendered = ->
  preprocess(this.data)

  margin = {
    left: 100
    bottom: 50
  }

  svg = @find("svg")
  width = $(svg).width() - margin.left
  height = $(svg).height() - margin.bottom

  chart = d3.select(svg).append("g")
    .attr("transform", "translate(#{margin.left}, 0)")
    # TODO this is not clipping
    .attr("clip-path", "rect(0, 0, #{width}, #{height})")

  x = d3.scale.linear()
    .domain([@data.instance.startTime, @data.instance.endTime])
    .range([0, width])

  # Create domain and labels; including a fake value for all users
  domain = (user._id for user in @data.users)

  domainLabels = (user.username for user in @data.users)

  y = d3.scale.ordinal()
    .domain(domain)
    .rangeBands([0, height], 0.2)

  bandWidth = y.rangeBand() / 3

  xAxis = d3.svg.axis()
    .orient("bottom")
    .scale(x)
    .tickFormat( (date) -> new Date(date).toLocaleTimeString() )

  yAxis = d3.svg.axis()
    .orient("left")
    .scale(y)
    .tickValues(domainLabels)

  svgX = chart.append("g")
    .attr("class", "x axis")
    .attr("transform", "translate(0, #{height})")

  svgY = chart.append("g")
    .attr("class", "y axis")
    .attr("transform", "translate(0, 0)")
    .call(yAxis)

  # Draw bands encompassing user actions
  chart.selectAll(".bands")
    .data(y.domain())
  .enter()
    .append("rect")
    .attr("class", "band")
    .attr("y", (id) -> y(id))
    .attr("width", width)
    .attr("height", y.rangeBand())

  # Draw actions
  chart.selectAll(".action")
    .data(@data.logs, (entry) -> entry._id)
  .enter().append("rect")
    .attr("class", logEntryClass)
    .attr("y", (entry) -> y(entry._userId) + vizType(entry) * bandWidth)
    .attr("width", vizPointWidth)
    .attr("height", bandWidth)
  .append("svg:title")
    .text((d) -> d.action || d._meta)

  # Draw chat
  chart.selectAll(".chat")
    .data(@data.chat, (msg) -> msg._id)
  .enter().append("rect")
    .attr("class", chatMsgClass)
    .attr("y", (msg) -> y(msg.userId) + 2*bandWidth)
    .attr("width", vizPointWidth)
    .attr("height", bandWidth)
  .append("svg:title")
    .text((d) -> d.text)

  redraw = ->
    svgX.call(xAxis)

    chart.selectAll(".action")
      .attr("x", (entry) -> x(entry._timestamp))

    chart.selectAll(".chat")
      .attr("x", (entry) -> x(entry.timestamp))

  # Reposition X stuff with appropriate zoom
  redraw()

  zoom = d3.behavior.zoom()
    .x(x)
    .scaleExtent([1, 20])
    .on("zoom", redraw)

  d3.select(svg).call(zoom)

Template.viz.rendered = ->
  @layout = "force"

  margin = {
    bottom: 20
  }

  svg = @find("svg.timeline")
  width = $(svg).width()
  height = $(svg).height() - margin.bottom

  chart = d3.select(svg).append("g")

  timeRange = [@data.instance.startTime, @data.instance.endTime]

  x = d3.scale.linear()
    .domain(timeRange)
    .range([0, width])

  y = d3.scale.ordinal()
    .domain([0..2])
    .rangeBands([0, height])

  xAxis = d3.svg.axis()
    .orient("bottom")
    .scale(x)
    .tickFormat( (date) -> new Date(date).toLocaleTimeString() )

  svgX = chart.append("g")
    .attr("class", "x axis")
    .attr("transform", "translate(0, #{height})")

  svgX.call(xAxis)

  chart.selectAll(".action")
    .data(@data.logs, (entry) -> entry._id)
  .enter().append("rect")
    .attr("class", logEntryClass)
    .attr("x", (entry) -> x(entry._timestamp))
    .attr("y", (entry) -> y(vizType(entry)))
    .attr("width", vizPointWidth)
    .attr("height", y.rangeBand())

  chart.selectAll(".chat")
    .data(@data.chat, (msg) -> msg._id)
  .enter().append("rect")
    .attr("class", chatMsgClass)
    .attr("x", (entry) -> x(entry.timestamp))
    .attr("y", y(2))
    .attr("width", vizPointWidth)
    .attr("height", y.rangeBand())

  ###
    Draw pie SVG
  ###

  padding = 5
  clusterPadding = 80

  piesvg = @find("svg.pies")
  pieHeight = $(piesvg).height()

  # Create nest operators for counting up actions and chat
  # Re-nest for different types of classification actions
  logNest = d3.nest()
    .key((entry) -> entry._userId)
    .key( entryActionType )
    .sortKeys(d3.ascending)
    .key( (entry) -> entry.action + " " + (entryActionField(entry) || "")  )
    .sortKeys(d3.ascending)
    .rollup( (leaves) -> { count: leaves.length } )

  chatNest = d3.nest()
    .key( (msg) -> msg.userId )
    .key( (msg) -> "chat" )
    .key( (msg) -> if msg.text.match(tags) then "tagged" else "undirected" )
    .rollup( (leaves) -> { count: leaves.length} )

  # Create a pack layout for users. This can have a little extra overage so the
  # circles are bigger in the force directed layout
  pack = d3.layout.pack()
    .sort(null)
    .size([width, Math.min(width, 1.25 * pieHeight)])
    # We create a one-time object to use this, but we don't want it to descend
    # into the per-user nested data, which has the 'children' key
    .children( (d) -> d.values unless d.children )
    # .value( (d) -> d.value )
    .padding(padding)

  clusters = {}

  clusterNest = d3.nest()
    .key( (d) -> d.cluster )
    .rollup (values) ->
      # Whenever we cluster users, store the biggest user of each cluster
      clusterUser = _.max(values, (c) -> c.value)
      clusters[clusterUser.cluster] = clusterUser
      # Still need to return the values themselves
      return values

  # Radius for per-user sunburst; arbitrary value that gets rescaled anyway
  r = 200
  maxRadius = 0

  partition = d3.layout.partition()
    .sort(null)
    .size([2 * Math.PI, r * r])
    .children( (d) -> d.values )
    .value( (d) -> d.values?.count );

  arc = d3.svg.arc()
    .startAngle((d) -> d.x )
    .endAngle((d) -> d.x + d.dx )
    .innerRadius((d) -> Math.sqrt(d.y) )
    .outerRadius((d) -> Math.sqrt(d.y + d.dy) );

  force = d3.layout.force()
    .size([width, pieHeight])
    # .friction(0.4) # So it's less bouncy when we are playing with time
    .gravity(.02)
    .charge(0)

  # Create a brush for adjusting the viewing region
  brush = d3.svg.brush()
    .x(x)
    .extent(timeRange)

  gBrush = chart.append("g")
    .attr("class", "brush")
    .call(brush)

  gBrush.selectAll("rect")
    .attr("height", height)

  brushed = (first) =>
    extent = brush.extent()
    # Merge nested actions up per user
    oldData = @pieData

    @pieData = logNest.entries filterLogs(@data.logs, extent)

    # merge nested chat entries
    chatData = chatNest.entries filterChat(@data.chat, extent)

    # Smush data together
    for record in @pieData
      chatRecords = _.find(chatData, (c) -> c.key is record.key)
      continue unless chatRecords?
      record.values = record.values.concat(chatRecords.values)

    pies = d3.select(piesvg).selectAll("g.pie")
      .data(@pieData, (d) -> d.key)

    # Create a container for each pie along with a circle that outlines it
    centers = pies.enter().append("g")
      .attr("class", "pie")
      .attr("transform", "translate(0,0)") # Default value for tweening
      .call(force.drag)

    centers.append("g")
      .attr("class", "scaler")
      .attr("transform", "scale(1,1)") # Ditto
    .append("circle")
      .attr("class", "outline")
      .attr("r", r)

    # Create the centering g element and the user name text field
    centers.append("svg:text")
    .attr("class", "caption")
    .attr("dy", "0.35em")
    .attr("text-anchor", "middle")

    pies.exit().remove()

    # Create a new selection for the path inside each data
    # Partition.nodes will fill in some crap for each users's data
    nodes = pies.select("g.scaler").selectAll("path")
      .data(partition.nodes)

    nodes.enter().append("path")
    nodes.exit().remove()

    nodes
      .attr("class", (d) ->
          switch
            when d.depth is 0 # Compute the largest category and assign this to the center
              maxChild = _.max(d.values, (c) -> c.value)
              d.cluster = maxChild.key || null
              "action " + maxChild.key
            when d.depth is 1 then "action type " + d.key
            when d.depth is 2 and d.parent.key is "chat" then "chat " + d.key
            when d.depth is 2 then "action " + d.key
        )
      .attr("d", arc)

    text = pies.select("text.caption")
    text.text((d) => _.find(@data.users, (u) -> u._id is d.key)?.username + " (#{d.value})" )

    # Resize circles and pack according to cluster
    # Create a temporary object and then immediately discard the top level
    # TODO compute more consistent pie sizes when not using force layout
    pack.nodes( { values: clusterNest.entries(@pieData) } )

    # TODO reduce explosion when going from non-force layout to force
    if @layout is "force" and oldData?
      # Use existing (x,y) positions to initialize when we keeping a force layout
      for d in @pieData
        if (od = _.find(oldData, (od) -> od.key is d.key ))
          d.x = od.x
          d.y = od.y
        else
          d.x = width / 2
          d.y = pieHeight / 2

    # Update size of maximum radius for collision function
    maxRadius = d3.max(@pieData, (d) -> d.r)

    # Reset data for force layout
    force.nodes(@pieData)

    @reposition()

  ###
  Clustered force-direct layout functions: http://bl.ocks.org/mbostock/7882658
  ###

  # Move d to be adjacent to the cluster node.
  recluster = (alpha) ->
    (d) ->
      cluster = clusters[d.cluster]
      return if cluster is d
      x = d.x - cluster.x
      y = d.y - cluster.y
      l = Math.sqrt(x * x + y * y)
      r = d.r + cluster.r
      unless l is r
        l = (l - r) / l * alpha
        d.x -= (x *= l)
        d.y -= (y *= l)
        cluster.x += x
        cluster.y += y
      return

  # Resolves collisions between d and all other circles.
  collide = (alpha) =>
    quadtree = d3.geom.quadtree(@pieData)
    (d) ->
      r = d.r + maxRadius + Math.max(padding, clusterPadding)
      nx1 = d.x - r
      nx2 = d.x + r
      ny1 = d.y - r
      ny2 = d.y + r
      quadtree.visit (quad, x1, y1, x2, y2) ->
        if quad.point and (quad.point isnt d)
          x = d.x - quad.point.x
          y = d.y - quad.point.y
          l = Math.sqrt(x * x + y * y)
          r = d.r + quad.point.r + (if d.cluster is quad.point.cluster then padding else clusterPadding)
          if l < r
            l = (l - r) / l * alpha
            d.x -= x *= l
            d.y -= y *= l
            quad.point.x += x
            quad.point.y += y
        x1 > nx2 or x2 < nx1 or y1 > ny2 or y2 < ny1
      return

  tick = (e) ->
    d3.select(piesvg).selectAll("g.pie")
    .each(recluster(10 * e.alpha * e.alpha))
    # Don't treat collisions too harshly, causes bouncing on transitions
    .each(collide(.5))
    .attr("transform", (d) -> "translate(#{d.x}, #{d.y})")

  simpleLayout = (data) ->
    layoutMargin = 50
    layoutPadding = 20
    currentX = layoutMargin
    currentY = layoutMargin
    gap = 100
    # Arrange circles in rows by size
    data.sort( (a, b) -> b.r - a.r )
    data.forEach (d) ->
      if currentX + 2*d.r > width
        currentX = layoutMargin
        currentY += 2*gap + layoutMargin

      # Reset gap to height of first item in a new row
      gap = d.r if currentX is layoutMargin

      d.x = currentX + d.r
      d.y = currentY + gap

      currentX += 2*d.r + layoutPadding

  @reposition = =>
    pies = d3.select(piesvg).selectAll("g.pie")

    # Resize pies smoothly
    pies.select("g.scaler")
    .transition()
    .attr "transform", (d) ->
        # s = Math.sqrt(d.value / max)
        s = d.r / 200
        return "scale(#{s}, #{s})"

    if @layout is "force" # Force layout; default
      force.on("tick.pies", tick)
      force.start()
    else
      force.stop()
      force.on("tick.pies", null)

      # Leave things in whatever playout was there before if fixed
      return if @layout is "fixed"

      if @layout is "sorted"
        simpleLayout(@pieData)
        # Animate to new positions
        pies.transition()
        .attr("transform", (d) -> "translate(#{d.x}, #{d.y})")

  brush.on("brushend", brushed)

  # First draw
  brushed(true)







