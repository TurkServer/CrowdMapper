preprocess = (data) ->
  logs = data.logs

  move_reclassify = 0
  unlink_reclassify = 0
  non_user = 0

  i = 0
  while i < logs.length
    if not logs[i]._userId?
      # Filter out non-user log items.
      non_user++

      logs.splice(i, 1)
      continue # no increment

    else if logs[i].action is "data-unlink"
      # Re-categorize link/unlink as data-move.
      # This won't be necessary other than for the pilot data.
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

  console.log "Moves re-classified: #{move_reclassify}", "Unlinks re-classified: #{unlink_reclassify}", "Non-user log items removed: #{non_user}"

tags = /[~@#]/

tickPosition = (entry) ->
  switch Util.logActionType(entry)
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

###
  Viz Parameters
###

vizPointWidth = 5

collapsedTimelineHeight = 70
# left and bottom margin of timelines
leftMargin = 90
bottomMargin = 30

# Cluster settings
padding = 5
clusterPadding = 80
# Radius for per-user sunburst; arbitrary value that gets rescaled anyway
scaleRadius = 200

Template.viz.created = ->
  preprocess(@data)

  @settings = new ReactiveDict()

Template.viz.helpers
  leftMargin: leftMargin
  data: (field) -> Template.instance().data[field]

Template.viz.rendered = ->
  ###
    Initialization functions
  ###
  @initTimeline = =>
    @timelineWidth = $(@svg).width() - leftMargin

    @timeline = d3.select(@svg).select("g.timeline")

    timeRange = [@data.instance.startTime, @data.instance.endTime]

    @timelineX = d3.scale.linear()
      .domain(timeRange)
      .range([0, @timelineWidth])

    @timelineY = d3.scale.ordinal()

    @timelineXaxis = d3.svg.axis()
      .orient("bottom")
      .scale(@timelineX)
      .tickFormat( (date) -> new Date(date).toLocaleTimeString() )

    @timelineYaxis = d3.svg.axis()
      .orient("left")
      .scale(@timelineY)

    # Create a background for bands, grid lines, etc that appear under data
    background = @timeline.select("g.chart-background")

    # Draw bands once for all users, these will collapse together
    bands = background.selectAll(".band")
      .data( (user._id for user in @data.users) )
    .enter().append("rect")
      .attr("class", "band")
      .attr("width", @timelineWidth)

    # Too slow to draw these via blaze; must draw with d3
    chart = @timeline.select("g.chart-data")

    # Draw actions
    chart.selectAll(".action")
      .data(@data.logs, (entry) -> entry._id)
    .enter().append("rect")
      .attr("class", logEntryClass)
      .attr("width", vizPointWidth)
    .append("svg:title")
      .text((d) -> d.action || d._meta)

    # Draw chat
    chart.selectAll(".chat")
      .data(@data.chat, (msg) -> msg._id)
    .enter().append("rect")
      .attr("class", chatMsgClass)
      .attr("width", vizPointWidth)
    .append("svg:title")
      .text((d) -> d.text)

    # Reposition X stuff with appropriate zoom
    @zoomTimeline()

    @zoom = d3.behavior.zoom()
      .x(@timelineX)
      .scaleExtent([1, 20])
      .on("zoom", @zoomTimeline)

    @timeline.call(@zoom)

    # Create a brush for adjusting the viewing region
    @brush = d3.svg.brush()
      .x(@timelineX)
      .extent(timeRange)

    @brush.on("brushend", @setBrush)

  @initPies = =>
    @sunbursts = d3.select(@svg).select("g.sunbursts")

    width = $(@svg).width()
    @pieHeight = $(@svg).height() - collapsedTimelineHeight

    # Create nest operators for counting up actions and chat
    # Re-nest for different types of classification actions
    @logNest = d3.nest()
      .key((entry) -> entry._userId)
      .key( Util.logActionType )
      .sortKeys(d3.ascending)
      .key( (entry) -> entry.action + " " + (entryActionField(entry) || "")  )
      .sortKeys(d3.ascending)
      .rollup( (leaves) -> { count: leaves.length } )

    @chatNest = d3.nest()
      .key( (msg) -> msg.userId )
      .key( (msg) -> "chat" )
      .key( (msg) -> if msg.text.match(tags) then "tagged" else "undirected" )
      .rollup( (leaves) -> { count: leaves.length} )

    # Create a pack layout for users. This can have a little extra overage so the
    # circles are bigger in the force directed layout
    @piesPack = d3.layout.pack()
      .sort(null)
      .size([width, Math.min(width, 1.25 * @pieHeight)])
      # We create a one-time object to use this, but we don't want it to descend
      # into the per-user nested data, which has the 'children' key
      .children( (d) -> d.values unless d.children )
      # .value( (d) -> d.value )
      .padding(padding)

    clusters = {}
    @pieClusters = clusters

    @piesClusterNest = d3.nest()
      .key( (d) -> d.cluster )
      .rollup (values) ->
          # Whenever we cluster users, store the biggest user of each cluster
          clusterUser = _.max(values, (c) -> c.value)
          clusters[clusterUser.cluster] = clusterUser
          # Still need to return the values themselves
          return values

    @pieMaxRadius = 0

    @piesPartition = d3.layout.partition()
      .sort(null)
      .size([2 * Math.PI, scaleRadius * scaleRadius])
      .children( (d) -> d.values )

    @piesArc = d3.svg.arc()
      .startAngle((d) -> d.x )
      .endAngle((d) -> d.x + d.dx )
      .innerRadius((d) -> Math.sqrt(d.y) )
      .outerRadius((d) -> Math.sqrt(d.y + d.dy) )

    @piesForce = d3.layout.force()
      .size([width, @pieHeight])
      # .friction(0.4) # So it's less bouncy when we are playing with time
      .gravity(.02)
      .charge(0)

  ###
    Redraw functions,
    separated for different granularity of modifications
  ###
  @zoomTimeline = =>
    @timeline.select(".timeline .x.axis").call(@timelineXaxis)
    x = @timelineX

    @timeline.selectAll(".action")
      .attr("x", (entry) -> x(entry._timestamp))

    @timeline.selectAll(".chat")
      .attr("x", (entry) -> x(entry.timestamp))

  expandTimeline = =>
    if @settings.equals("vizType", "time")
      height = $(@svg).height() - bottomMargin
      domain = (user._id for user in @data.users)

      # update Y domain
      @timelineY.domain( domain )

      domainLabels = domainLabels = (user.username for user in @data.users)

      @timelineYaxis.tickValues(domainLabels)

      # Remove brush
      @timeline.select("g.brush").remove()
    else
      height = collapsedTimelineHeight

      # Everything should map to the same value on this domain
      @timelineY.domain( [ 0 ] )
      @timelineYaxis.tickValues(["Everyone"])

      # Draw brush
      @timeline.select("g.brush")
      .call(@brush)
      .selectAll("rect") # Set initial height of brush
      .attr("height", collapsedTimelineHeight)

      # Reset x zoom when collapsing
      # TODO animate this in D3 3.3 or later using zoom.event
      @zoom.scale(1)
      @zoom.translate([0, 0])
      @zoomTimeline()
      # Make sure brushed area is up to date after this re-zoom
      @setBrush()

    @timelineY.rangeBands([0, height], 0.2)
    bandWidth = @timelineY.rangeBand() / 3

    tDuration = 600
    y = @timelineY
    ySVG = @timelineYaxis

    d3.select(@timeline)
      .transition()
      .duration(tDuration)
      .each ->
        # Transition various items selected from timeline
        # Inside this function, the transition duration is shared

        # Redraw axes and labels
        this.select(".x.axis")
          .transition()
          .attr("transform", "translate(0, #{height})")

        this.select(".y.axis")
          .transition()
          .call(ySVG)

        this.select(".brush rect")
          .transition()
          .attr("height", height)

        # TODO: behavior of ordinal scale changed in 3.4. Must manually revert to 0 below for collapsed timeline, but it can change if we modify the timeline position.
        defaultY = y(0)

        # Transition y positions of bands and events
        this.selectAll(".action")
          .transition()
          .attr("y", (entry) -> (y(entry._userId) || defaultY) + tickPosition(entry) * bandWidth)
          .attr("height", bandWidth)

        this.selectAll(".chat")
          .transition()
          .attr("y", (msg) -> (y(msg.userId) || defaultY) + 2*bandWidth)
          .attr("height", bandWidth)

        this.select(".chart-background").selectAll(".band")
          .transition()
          .attr("y", (id) -> y(id) || defaultY ) # Should just be 0 -> 0 for single band
          .attr("height", y.rangeBand())

    # Move sunbursts out of way
    @sunbursts.transition().duration(tDuration)
      .attr("transform", "translate(0, #{height})")

  @setBrush = =>
    unless @brush.empty()
      extent = @brush.extent()
    else
      extent = @timelineX.domain()

    @settings.set("brushExtent", extent)

  brushTimeline = =>
    extent = @settings.get("brushExtent")
    # Redraw if pie weights change
    @settings.get("pieWeighting")

    # Merge nested actions up per user
    oldData = @pieData

    @pieData = @logNest.entries filterLogs(@data.logs, extent)

    # merge nested chat entries
    chatData = @chatNest.entries filterChat(@data.chat, extent)

    # Smush data together
    for record in @pieData
      chatRecords = _.find(chatData, (c) -> c.key is record.key)
      continue unless chatRecords?
      record.values = record.values.concat(chatRecords.values)

    pies = @sunbursts.selectAll("g.pie")
      .data(@pieData, (d) -> d.key)

    # Create a container for each pie along with a circle that outlines it
    centers = pies.enter().append("g")
      .attr("class", "pie")
      .attr("transform", "translate(0,0)") # Default value for tweening
      .call(@piesForce.drag)

    centers.append("g")
      .attr("class", "scaler")
      .attr("transform", "scale(1,1)") # Ditto
    .append("circle")
      .attr("class", "outline")
      .attr("r", scaleRadius)

    # Create the centering g element and the user name text field
    centers.append("svg:text")
      .attr("class", "caption")
      .attr("dy", "0.35em")
      .attr("text-anchor", "middle")

    pies.exit().remove()

    # Create a new selection for the path inside each data
    # Partition.nodes will fill in some crap for each users's data
    nodes = pies.select("g.scaler").selectAll("path")
      .data(@piesPartition.nodes)

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
      .attr("d", @piesArc)

    text = pies.select("text.caption")
    text.text (d) =>
      _.find(@data.users, (u) -> u._id is d.key)?.username + " (#{d.value.toFixed(2)})"

    # Resize circles and pack according to cluster
    # Create a temporary object and then immediately discard the top level
    # This also computes new positions for all of the pies
    # TODO compute more consistent pie sizes when not using force layout
    @piesPack.nodes( { values: @piesClusterNest.entries(@pieData) } )

    # TODO reduce explosion when going from non-force layout to force
    width = $(@svg).width()

    # Use existing (x,y) positions to initialize when we keeping a force layout
    if @settings.equals("pieLayout", "force") and oldData?
      for d in @pieData
        if (od = _.find(oldData, (od) -> od.key is d.key ))
          d.x = od.x
          d.y = od.y
        else
          # For things that didn't exist before, start them in random places
          d.x = Math.random() * width
          d.y = Math.random() * @pieHeight

    # Update size of maximum radius for collision function
    @pieMaxRadius = d3.max(@pieData, (d) -> d.r)

    # Reset data for force layout
    @piesForce.nodes(@pieData)

  # Compute pie sizes and positions for simple layout
  @layoutPiesSimple = ->
    width = $(@svg).width()

    layoutMargin = 50
    layoutPadding = 20
    currentX = layoutMargin
    currentY = layoutMargin
    gap = 100

    # Arrange circles in rows by size
    @pieData.sort( (a, b) -> b.r - a.r )
    @pieData.forEach (d) ->
      if currentX + 2*d.r > width
        currentX = layoutMargin
        currentY += 2*gap + layoutMargin

      # Reset gap to height of first item in a new row
      gap = d.r if currentX is layoutMargin

      d.x = currentX + d.r
      d.y = currentY + gap

      currentX += 2*d.r + layoutPadding

  # Redraw pie sizes and locations
  repositionPies = =>
    layout = @settings.get("pieLayout")
    # Also re-position if re-weighted
    @settings.get("pieWeighting")

    pies = @sunbursts.selectAll("g.pie")

    # Resize pies smoothly
    pies.select("g.scaler")
      .transition()
      .attr "transform", (d) ->
          # s = Math.sqrt(d.value / max)
          s = d.r / 200
          return "scale(#{s}, #{s})"

    # Start force layout if appropriate
    if layout is "force"
      @piesForce.on("tick.pies", @forceTick)
      @piesForce.start()
    else
      @piesForce.stop()
      @piesForce.on("tick.pies", null)

    # Leave things in whatever playout was there before if fixed
    return if @layout is "fixed"

    if layout is "sorted"
      @layoutPiesSimple()
      # Animate to new positions
      pies.transition()
        .attr("transform", (d) -> "translate(#{d.x}, #{d.y})")

  @forceTick = (e) =>
    @sunbursts.selectAll("g.pie")
      .each(@recluster(10 * e.alpha * e.alpha))
      # Don't treat collisions too harshly, causes bouncing on transitions
      .each(@collide(.5))
      .attr("transform", (d) -> "translate(#{d.x}, #{d.y})")

  ###
  Clustered force-direct layout functions: http://bl.ocks.org/mbostock/7882658
  ###

  # Move d to be adjacent to the cluster node.
  @recluster = (alpha) =>
    clusters = @pieClusters
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
  @collide = (alpha) =>
    maxRadius = @pieMaxRadius
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

  pieWeighting = =>
    sliceValue = if @settings.equals("pieWeighting", "scaled")
      weights = @data.weights
      # TODO A little bit of hacky handling here, which we should clean up
      (d) ->
        count = d.values?.count
        tag = d.key.split(" ")[0]
        # No parent at this point, unfortunately
        if tag is "tagged" or tag is "undirected"
          value = weights.chat * count
        else
          value = count * ( weights[tag] || 0)
        # Return value in minutes
        return value / 60000
    else
      (d) -> d.values?.count

    @piesPartition.value(sliceValue)

  # Initial draw
  @svg = @find("svg")
  @initTimeline()

  @initPies()

  # Default setting for nav
  @settings.set("vizType", "pies")
  # Grab settings from rendered template
  for field in [ "pieLayout", "pieWeighting" ]
    @settings.set( field, @$("input[name=#{field}]:checked").val() )

  @setBrush()

  @autorun(pieWeighting)
  @autorun(expandTimeline)

  # Draw pies
  @autorun(brushTimeline)
  @autorun(repositionPies)

Template.viz.events
  "click .nav a": (e, t) ->
    e.preventDefault()
    target = $(e.target).data("target")
    t.settings.set("vizType", target)

  "change input[name=pieLayout]": (e, t) ->
    t.settings.set("pieLayout", e.target.value)

  "change input[name=pieWeight]": (e, t) ->
    t.settings.set("pieWeighting", e.target.value)

