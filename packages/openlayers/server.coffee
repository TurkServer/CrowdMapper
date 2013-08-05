# TEMPORARY - load up local openlayers repo, see https://github.com/meteor/meteor/issues/1229
connect = Npm.require('connect')

RoutePolicy.declare('/lib', 'network')

WebApp.connectHandlers
  .use(connect.bodyParser())
  .use('/lib', connect.static("/home/mao/projects/openlayers/lib"))
