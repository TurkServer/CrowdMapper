Npm.depends({
    connect: "2.7.10"
});

var both = ['client', 'server'];

Package.on_use(function (api) {
    api.use('coffeescript', both);
    api.use(['routepolicy', 'webapp'], 'server');

    api.add_files('client.html', 'client');
    api.add_files('server.coffee', 'server');
});
