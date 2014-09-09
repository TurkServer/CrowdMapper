computeGraph = (occurrences) ->
  # compute number of occurrences for each tweet
  nodes = d3.nest()
    .key(Number)
    .rollup( (leaves) -> leaves.length )
    .entries($.map(occurrences, Object))

  console.log nodes

  # Compute co-occurrences for each pair
  links = []

  console.log links

  return [nodes, links]

Template.overviewTagging.rendered = ->
  console.log this.data

  [nodes, links] = computeGraph(this.data)

  svg = @find("svg")
  width = $(svg).width()
  height = $(svg).height()

  graph = d3.select(svg).append("g")

  force = d3.layout.force()
    .size([width, height])
    .charge(0) # Disabled since we have a custom repulsion function
