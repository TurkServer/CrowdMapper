Npm.depends({
    connect: "2.9.0" // Current as of 0.6.6, but find and use handle from WebApp
});

Package.on_use(function (api) {
    api.use('coffeescript');
    api.use(['routepolicy', 'webapp'], 'server');

    api.add_files('client.html', 'client');
    api.add_files('server.coffee', 'server');
});
