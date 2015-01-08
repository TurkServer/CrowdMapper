// This is used to send RPC requests over ZeroMQ to Python
Npm.depends({
  zerorpc: "0.9.3"
});

Package.on_use(function (api) {
  api.use("coffeescript");
  api.use("stylus");
  api.use("templating");
  api.use("reactive-dict");

  api.use("underscore");

  // use versions of these specified in main project
  api.use("mizzao:turkserver");
  api.use("mizzao:jquery-ui");
  api.use("iron:router");
  api.use("d3js:d3");
  api.use("aslagle:reactive-table");

  api.addFiles("util.coffee");
  api.addFiles("common.coffee");

  api.addFiles([
    "client/viz.styl",
    "client/routes.coffee",
    "client/graphing.coffee",
    "client/viz.html",
    "client/viz.coffee",
    "client/overview.html",
    "client/overview.coffee",
    "client/tagging.html",
    "client/tagging.coffee",
    "client/box.js", // from http://bl.ocks.org/jensgrubert/7789216
    "client/groupPerformance.html",
    "client/groupPerformance.coffee",
    "client/groupSlices.html",
    "client/groupSlices.coffee",
    "client/indivPerformance.html",
    "client/indivPerformance.coffee",
    "client/specialization.html",
    "client/specialization.coffee"
  ], "client");

  api.addFiles('rpc.coffee', 'server');

  api.addFiles('replay.coffee', 'server');
  api.addFiles('aggregation.coffee', 'server');
  api.addFiles('analysis.coffee', 'server');

  // Exports
  api.export('Analysis');
  api.export('ReplayHandler', 'server');

  api.export('AdminController', 'client');
  // Make global available only in this package
  api.export('Util', {testOnly: true});
});

