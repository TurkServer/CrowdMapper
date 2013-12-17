Handlebars.registerHelper "debug", ->
  console.log arguments

# Register withif helper only if it doesn't already exist
unless Handlebars._default_helpers.withif
  Handlebars.registerHelper "withif", (obj, options) ->
    if obj then options.fn(obj) else options.inverse(this)
