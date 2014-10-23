// This is used to send RPC requests over ZeroMQ to Python
Npm.depends({
  zerorpc: "0.9.3"
});

Package.on_use(function (api) {
  api.use("coffeescript", "server");

  api.add_files('server.coffee', 'server');

  api.export('Analysis', 'server');
});
