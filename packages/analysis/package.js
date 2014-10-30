// This is used to send RPC requests over ZeroMQ to Python
Npm.depends({
  zerorpc: "0.9.3"
});

Package.on_use(function (api) {
  api.use("coffeescript");
  api.use("stylus");
  api.use("templating");

  api.use("d3");

  api.use("mizzao:turkserver");
  api.use("iron:router");

  api.addFiles([
    "client/viz.styl",
    "client/routes.coffee",
    "client/viz.html",
    "client/viz.coffee",
    "client/overview.html",
    "client/overview.coffee",
    "client/groupPerformance.html",
    "client/groupPerformance.coffee",
    "client/box.js", // from http://bl.ocks.org/jensgrubert/7789216
    "client/indivPerformance.html",
    "client/indivPerformance.coffee"
  ], "client");

  api.addFiles('rpc.coffee', 'server');

  api.addFiles('replay.coffee', 'server');
  api.addFiles('aggregation.coffee', 'server');
  api.addFiles('analysis.coffee', 'server');

  // Exports
  api.export('Analysis', 'server');
  api.export('ReplayHandler', 'server');

  api.export('AdminController', 'client');
});

