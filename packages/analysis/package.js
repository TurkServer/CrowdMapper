// This is used to send RPC requests over ZeroMQ to Python
Npm.depends({
  zerorpc: "0.9.3"
});

Package.on_use(function (api) {
  api.use("coffeescript", "server");

  api.use("mizzao:turkserver");

  api.add_files('rpc.coffee', 'server');

  api.add_files('replay.coffee', 'server');
  api.add_files('analysis.coffee', 'server');

  api.export('Analysis', 'server');
  api.export('ReplayHandler', 'server');
});
