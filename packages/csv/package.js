Npm.depends({
    csv: "0.3.5"
});

Package.on_use(function (api) {
    api.add_files('server.js', 'server');

    api.export('csv');
});
