Template.datastream.data = ->
  Datastream.find()

Template.dataItem.rendered = ->
  $(this.firstNode).draggable
    addClasses: false
    revert: "invalid"
    zIndex: 1000
    cursorAt: { top: 0, left: 0 }
    helper: ->
      # Set explicit width on the clone
      currentWidth = $(this).width()
      return $(this).clone().width(currentWidth)
