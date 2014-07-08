preprocess = (data) ->
  # data-unlink followed by data-link (in the near future) should be
  # reclassified as a "data-move" action
  # This won't be necessary other than for the pilot data.
  logs = data.logs
  i = 0
  while i < logs.length
    if logs[i].action is "data-unlink"
      j = i
      while ++j < logs.length and (j - i) < 5
        if logs[j].action is "data-link" and logs[j].dataId is logs[i].dataId
          logs[i].action = "data-move"
          logs[i].fromEventId = logs[i].eventId
          logs[i].toEventId = logs[j].eventId

          delete logs[i].eventId
          logs.splice(j, 1)
          break
    i++

Router.map ->
  @route 'viz',
    path: 'viz/:groupId'
    onBeforeAction: (pause) ->
      unless TurkServer.isAdmin()
        @render("loadError")
        pause()
    waitOn: ->
      @readyDep = new Deps.Dependency
      @readyDep.isReady = false;

      Meteor.call "getMapperData", this.params.groupId, (err, res) =>
        bootbox.alert(err) if err

        preprocess(res)
        this.mapperData = res

        @readyDep.isReady = true;
        @readyDep.changed()

      return {
        ready: =>
          @readyDep.depend()
          return @readyDep.isReady
      }
    data: ->
      @readyDep.depend()
      return this.mapperData
    action: ->
      if this.ready()

        this.render()

tags = /[~@#]/

Template.viz.events
  "click nav a": (e, t) ->
    e.preventDefault()
    target = $(e.target).data("target")

    t.$(".stack .item").removeClass("active")
    t.$(".stack .item.#{target}").addClass("active")

Template.viz.rendered = ->
  this.$(".stack .item").removeClass("active")
  this.$(".stack .item").first().addClass("active")

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

Template.vizActionsOverTime.rendered = ->
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

Template.vizActionPies.events
  "change input[name=pieLayout]": (e, t) ->
    t.layout = e.target.value
    t.reposition()

Template.vizActionPies.rendered = ->
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

  # Create a pack layout for users
  pack = d3.layout.pack()
    # .sort((d) -> d.key)
    .size([pieHeight, width])
    .children((d) -> d.pies )
    # .value( (d) -> d.value )
    .padding(5)

  # Radius for per-user sunburst; arbitrary value that gets rescaled anyway
  r = 200

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

  # Create a brush for adjusting the viewing region
  brush = d3.svg.brush()
    .x(x)
    .extent(timeRange)

  gBrush = chart.append("g")
    .attr("class", "brush")
    .call(brush)

  gBrush.selectAll("rect")
    .attr("height", height)

  brushed = =>
    extent = brush.extent()
    # Merge nested actions up per user
    data = logNest.entries filterLogs(@data.logs, extent)

    # merge nested chat entries
    chatData = chatNest.entries filterChat(@data.chat, extent)

    # Smush data together
    for record in data
      chatRecords = _.find(chatData, (c) -> c.key is record.key)
      continue unless chatRecords?
      record.values = record.values.concat(chatRecords.values)

    pies = d3.select(piesvg).selectAll("g.pie")
      .data(data, (d) -> d.key)

    # Create a container for each pie along with a circle that outlines it
    centers = pies.enter().append("g")
      .attr("class", "pie")
      .attr("transform", "translate(0,0)") # Default value for tweening

    centers.append("g")
      .attr("class", "center")
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
    nodes = pies.select("g.center").selectAll("path")
      .data(partition.nodes)

    nodes.enter().append("path")
    nodes.exit().remove()

    nodes
      .attr("class", (d) ->
          switch
            when d.depth is 0 then "root"
            when d.depth is 1 then "action type " + d.key
            when d.depth is 2 and d.parent.key is "chat" then "chat " + d.key
            when d.depth is 2 then "action " + d.key
        )
      .attr("d", arc)

    text = pies.select("text.caption")
    text.text((d) => _.find(@data.users, (u) -> u._id is d.key)?.username + " (#{d.value})" )

    # Resize circles and pack to new positions
    # Create a temporary object and then immediately discard the top level
    pack.nodes({key: "root", pies: data})

    @reposition()

  brush.on "brushend", brushed

  @reposition = =>
    pies = d3.select(piesvg).selectAll("g.pie")

    pies.select("g.center").transition()
    .attr "transform", (d) ->
        # s = Math.sqrt(d.value / max)
        s = d.r / 200
        return "scale(#{s}, #{s})"

    # Leave things in whatever playout was there before if fixed
    return if @layout is "fixed"

    if @layout is "sorted"
      # TODO implement row layout

    else # Aggregate layout; default
      # Recompute pie sizes and re-pack into the area
      # Position pies based on new packed positions
      pies.transition()
      .attr "transform", (d) ->
          # Use transposed packing as it seems to be more space efficient horizontally
          return "translate(#{d.y}, #{d.x})"

  # First draw
  brushed()







