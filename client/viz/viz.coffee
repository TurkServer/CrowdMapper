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

Template.viz.rendered = ->
  console.log @data.instance
  console.log "users", @data.users
  console.log "logs", @data.logs
  console.log "chat", @data.chat

entryActionField = (entry) ->
  field = null
  for k, v of entry?.fields
    field = k
    break
  return field

Template.vizActionsOverTime.rendered = ->
  margin = {
    left: 100
    bottom: 50
  }

  pointWidth = 5

  svg = @find("svg")
  width = $(svg).width() - margin.left
  height = $(svg).height() - margin.bottom

  chart = d3.select(svg).append("g")
    .attr("transform", "translate(#{margin.left}, 0)")
    .attr("clip-path", "rect(0, 0, #{width}, #{height})")

  x = d3.scale.linear()
    .domain([@data.instance.startTime, @data.instance.endTime])
    .range([0, width])

  # Create domain and labels; including a fake value for all users
  domain = (user._id for user in @data.users)
  domain.push("all")

  domainLabels = (user.username for user in @data.users)
  domainLabels.push("All")

  y = d3.scale.ordinal()
    .domain(domain)
    .rangeBands([0, height], 0.2)

  bandWidth = y.rangeBand() / 3

  xAxis = d3.svg.axis()
    .orient("bottom")
    .scale(x)
    .tickFormat( (date) -> new Date(date).toLocaleString() )

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

  formatAction = (_, overriddenUserId) ->
    this
    .attr("class", (entry) ->
        field = entryActionField(entry) || ""
        return "action #{entry.action || entry._meta} #{field}"
      )
    .attr("y", (entry) ->
        val = y(overriddenUserId || entry._userId)
        # Offset filtering/verification stuff
        switch entry.action
          when "data-unlink", "data-hide", "event-vote", "event-unvote"
          else
            val += bandWidth
        return val
      )
    .attr("width", pointWidth)
    .attr("height", bandWidth)

  # Draw actions
  chart.selectAll(".action")
    .data(@data.logs, (entry) -> entry._id)
  .enter().append("rect")
    .call(formatAction)
  .append("svg:title")
    .text((d) -> d.action || d._meta)

  # TODO if updating in real time, can't overload the .action class
  chart.selectAll(".action.all")
    .data(@data.logs, (entry) -> entry._id)
  .enter().append("rect")
    .call(formatAction, "all")
  # Don't append SVG title

  formatChat = (_, overriddenUserId) ->
    this
    .attr("class", (msg) ->
      if msg.text.match(tags)
        tagged = "tagged"
      "chat #{tagged}"
    )
    .attr("y", (msg) ->
        y(overriddenUserId || msg.userId) + 2*bandWidth
      )
    .attr("width", pointWidth)
    .attr("height", bandWidth)

  # Draw chat
  chart.selectAll(".chat")
    .data(@data.chat, (msg) -> msg._id)
  .enter()
    .append("rect")
    .call(formatChat)
  .append("svg:title")
    .text((d) -> d.text)

  chart.selectAll(".chat.all")
    .data(@data.chat, (msg) -> msg._id)
  .enter()
    .append("rect")
    .call(formatChat, "all")

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

Template.vizActionPies.rendered = ->
  # Count up actions and chat
  fieldNest = d3.nest()
    .key( entryActionField )
    .rollup( (leaves) -> { count: leaves.length } )

  logNest = d3.nest()
    .key((entry) -> entry._userId)
    .key((entry) -> entry.action)
    .rollup( (leaves) ->
      if leaves[0].action is "event-update"
        # Third level nest for different types of event updates
        return fieldNest.entries(leaves)
      return { count: leaves.length }
    )

  chatNest = d3.nest()
    .key( (msg) -> msg.userId )
    .key( (msg) -> "chat" )
    .key( (msg) -> if msg.text.match(tags) then "tagged" else "undirected" )
    .rollup( (leaves) -> { count: leaves.length} )

  # Merge nested actions up per user
  data = logNest.entries(@data.logs)

  # merge nested chat entries
  chatData = chatNest.entries(@data.chat)
  for record in data
    chatRecords = _.find(chatData, (c) -> c.key is record.key)
    continue unless chatRecords?
    record.values = record.values.concat(chatRecords.values)

  # Margin and radius
  m = 0
  r = 180

  gs = d3.select(@find(".pies")).selectAll("svg")
    .data(data)
  .enter().append("svg:svg")
    .attr("class", "viz")
    .attr("width", (r + m) * 2)
    .attr("height", (r + m) * 2)
  .append("svg:g")
    .attr("transform", "translate(#{r+m}, #{r+m})")

  pies = gs.append("svg:g")

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

  # Create a new selection for the path inside each data
  pies.selectAll("path")
    .data(partition.nodes)
  .enter().append("path")
    .attr("class", (d) ->
      switch
        when d.depth is 0 then "root"
        when d.depth is 1 and d.key is "chat" then "chat"
        when d.depth is 1 then "action " + d.key
        when d.depth is 2 and d.parent.key is "chat" then "chat " + d.key
        when d.depth is 2 then "action event-update " + d.key
    )
    .attr("d", arc)
    .style("fill-rule", "evenodd")

  # Data has been modified quite a bit now and will have a value in each node
  max = d3.max(data, (d) -> d.value)

  gs.append("svg:text")
    .attr("dy", "0.35em")
    .attr("text-anchor", "middle")
    .text((d) => _.find(@data.users, (u) -> u._id is d.key)?.username + " (#{d.value})" )

  pies.attr "transform", (d) ->
    s = Math.sqrt(d.value / max)
    "scale(#{s}, #{s})"











