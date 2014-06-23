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

  y = d3.scale.ordinal()
    .domain(user._id for user in @data.users)
    .rangeBands([0, height], 0.2)

  bandWidth = y.rangeBand() / 3

  xAxis = d3.svg.axis()
    .orient("bottom")
    .scale(x)
    .tickFormat( (date) -> new Date(date).toLocaleString() )

  yAxis = d3.svg.axis()
    .orient("left")
    .scale(y)
    .tickValues(user.username for user in @data.users)

  svgX = chart.append("g")
    .attr("class", "x axis")
    .attr("transform", "translate(0, #{height})")

  svgY = chart.append("g")
    .attr("class", "y axis")
    .attr("transform", "translate(0, 0)")
    .call(yAxis)

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
  .enter()
    .append("rect")
    .attr("class", (entry) ->
      field = ""
      for k, v of entry?.fields
        field = k
        break
      return "action #{entry.action || entry._meta} #{field}"
    )
    .attr("y", (entry) ->
      val = y(entry._userId)
      # Offset filtering/verification stuff
      switch entry.action
        when "data-unlink", "data-hide", "event-vote", "event-unvote"
        else
          val += bandWidth
      return val
    )
    .attr("width", pointWidth)
    .attr("height", bandWidth)
  .append("svg:title")
    .text((d) -> d.action || d._meta)

  # Draw chat
  chart.selectAll(".chat")
    .data(@data.chat, (msg) -> msg._id)
  .enter()
    .append("rect")
    .attr("class", (msg) ->
      if msg.text.match(tags)
        tagged = "tagged"
      "chat #{tagged}"
    )
    .attr("y", (entry) ->
      y(entry.userId) + 2*bandWidth
    )
    .attr("width", pointWidth)
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









