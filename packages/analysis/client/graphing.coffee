# Helper functions for d3 graphs and visualizations
colors = d3.scale.category10().domain( [0...10] )

Util.groupColor = (size) -> colors(Math.log(size) / Math.LN2)

Template.registerHelper "sizeColor", (size) ->
  size ?= @nominalSize
  return Util.groupColor(size)
