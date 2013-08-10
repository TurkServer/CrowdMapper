#!/bin/bash

# OpenLayers 2.13.1 (actual js version is on dev)
curl -L http://dev.openlayers.org/releases/OpenLayers-2.13.1/OpenLayers.js > client/compatibility/OpenLayers.js
# below not needed since in client/compatibility
# echo 'window.OpenLayers = OpenLayers;' >> client/lib/OpenLayers.js
curl -L http://dev.openlayers.org/releases/OpenLayers-2.13.1/theme/default/style.css > client/compatibility/OpenLayers.css

# jQuery-UI 1.10.3
curl -L http://code.jquery.com/ui/1.10.3/jquery-ui.min.js > client/compatibility/jquery-ui.min.js
curl -L http://code.jquery.com/ui/1.10.3/themes/smoothness/jquery-ui.css > client/compatibility/jquery-ui.css
