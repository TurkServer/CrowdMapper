// This is used to send RPC requests over ZeroMQ to Python
Npm.depends({
  json2csv: "2.2.1",
  "simple-statistics": "0.9.0",
});

Package.on_use(function (api) {
  api.use("coffeescript");
  api.use("stylus");
  api.use("templating");
  api.use("tracker");
  api.use("reactive-dict");

  api.use("underscore");

  // use versions of these specified in main project
  api.use("mizzao:turkserver");
  api.use("mizzao:jquery-ui");
  api.use("iron:router");
  api.use("d3js:d3");
  api.use("aslagle:reactive-table");

  // Use local csv package to generate stuff
  api.use("csv");

  // Basic stats in browser
  api.addFiles('.npm/package/node_modules/simple-statistics/src/simple_statistics.js', 'client');

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
    "client/groupScatter.html",
    "client/groupScatter.coffee",
    "client/groupPerformance.html",
    "client/groupPerformance.coffee",
    "client/groupSlices.html",
    "client/groupSlices.coffee",
    "client/indivPerformance.html",
    "client/indivPerformance.coffee"
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

