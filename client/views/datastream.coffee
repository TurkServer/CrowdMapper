Template.datastream.data = ->
  Datastream.find()

Template.dataItem.rendered = ->
  $(this.firstNode).draggable
    addClasses: false
    # containment: "window"
    cursorAt: { top: 0, left: 0 }
    distance: 5
    revert: "invalid"
    scroll: false
    zIndex: 1000

    helper: ->
      # Set explicit width on the clone
      currentWidth = $(this).width()
      return $(this).clone().width(currentWidth)
