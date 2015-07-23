Package.on_use(function (api) {
  api.use("mizzao:build-fetcher@0.2.0");

  api.addFiles('embedly.fetch.json', 'client');
  api.addFiles('key.js', 'client');
});
