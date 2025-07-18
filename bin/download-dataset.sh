#!/bin/bash

OUTPUT_FILE_OSM="data/live-osm-data.geojson"
OUTPUT_FILE_TEJIDO="data/tejido.geojson"

mkdir -p data

if [ ! -f "$OUTPUT_FILE_OSM" ]; then
    echo "Error: OSM data file data/live-osm-data.geojson not found. Please download it first."
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
