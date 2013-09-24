Handlebars.registerHelper "debug", ->
  console.log arguments

Handlebars.registerHelper "withif", (obj, options) ->
  if obj then options.fn(obj) else options.inverse(this)
