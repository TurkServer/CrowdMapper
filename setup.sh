#!/bin/bash
curl -L http://dev.openlayers.org/releases/OpenLayers-2.13.1/OpenLayers.js > client/compatibility/OpenLayers.js
# below not needed since in client/compatibility
# echo 'window.OpenLayers = OpenLayers;' >> client/lib/OpenLayers.js
