Package.on_use(function (api) {
    // TODO serve the OpenLayers.js and css from here as well

    var path = Npm.require('path');

    // Two bad options, but we won't use this one because it doesn't read this dir.
//    var fs = Npm.require('fs');
//    var files = fs.readdirSync('.');
//    console.log(files);

    api.add_files(path.join("openlayers", "img", "blank.gif"));
    api.add_files(path.join("openlayers", "img", "cloud-popup-relative.png"));
    api.add_files(path.join("openlayers", "img", "drag-rectangle-off.png"));
    api.add_files(path.join("openlayers", "img", "drag-rectangle-on.png"));
    api.add_files(path.join("openlayers", "img", "east-mini.png"));
    api.add_files(path.join("openlayers", "img", "layer-switcher-maximize.png"));
    api.add_files(path.join("openlayers", "img", "layer-switcher-minimize.png"));
    api.add_files(path.join("openlayers", "img", "marker-blue.png"));
    api.add_files(path.join("openlayers", "img", "marker-gold.png"));
    api.add_files(path.join("openlayers", "img", "marker-green.png"));
    api.add_files(path.join("openlayers", "img", "marker.png"));
    api.add_files(path.join("openlayers", "img", "measuring-stick-off.png"));
    api.add_files(path.join("openlayers", "img", "measuring-stick-on.png"));
    api.add_files(path.join("openlayers", "img", "north-mini.png"));
    api.add_files(path.join("openlayers", "img", "panning-hand-off.png"));
    api.add_files(path.join("openlayers", "img", "panning-hand-on.png"));
    api.add_files(path.join("openlayers", "img", "slider.png"));
    api.add_files(path.join("openlayers", "img", "south-mini.png"));
    api.add_files(path.join("openlayers", "img", "west-mini.png"));
    api.add_files(path.join("openlayers", "img", "zoombar.png"));
    api.add_files(path.join("openlayers", "img", "zoom-minus-mini.png"));
    api.add_files(path.join("openlayers", "img", "zoom-plus-mini.png"));
    api.add_files(path.join("openlayers", "img", "zoom-world-mini.png"));
});
