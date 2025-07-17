#!/bin/bash

OUTPUT_FILE_OSM="data/live-osm-data.geojson"
OUTPUT_FILE_TEJIDO="data/tejido.geojson"

OVERPASS_URL="https://overpass-api.de/api/interpreter"
QUERY='[out:json][timeout:900];
area["name"="Buenos Aires"]["boundary"="administrative"]["admin_level"="8"]->.searchArea;
(
  way["building"](area.searchArea);
  relation["building"](area.searchArea);
);
out body;
>;
out skel qt;'

mkdir -p data

echo "Fetching OSM building data for Buenos Aires..."
curl -s -X POST -d "$QUERY" "$OVERPASS_URL" -o "$OUTPUT_FILE_OSM"

if [ -s "$OUTPUT_FILE_OSM" ]; then
    echo "OSM data successfully saved to $OUTPUT_FILE_OSM"
else
    echo "Error: Failed to fetch OSM data or output file is empty"
    exit 1
fi

echo "Downloading Tejido Urbano dataset..."
curl -s "https://cdn.buenosaires.gob.ar/datosabiertos/datasets/secretaria-de-desarrollo-urbano/tejido-urbano/tejido.geojson" -o "$OUTPUT_FILE_TEJIDO"

if [ -s "$OUTPUT_FILE_TEJIDO" ]; then
    echo "Tejido Urbano dataset successfully saved to $OUTPUT_FILE_TEJIDO"
else
    echo "Error: Failed to fetch Tejido Urbano dataset or output file is empty"
    exit 1
fi
