#!/bin/bash
# Downloads Obras Iniciadas (AGC, data.buenosaires.gob.ar/dataset/obras-iniciadas, CC-BY-2.5-AR)
# to data/obras-iniciadas-<download date>.csv: building works started in the city, with their
# SMP, type and start date (PLAN 4.10). The city updates it monthly; each run names its copy.

set -e

URL="https://cdn.buenosaires.gob.ar/datosabiertos/datasets/agencia-gubernamental-de-control/obras-iniciadas/obras_iniciadas.csv"
OUTPUT_FILE="data/obras-iniciadas-$(date +%F).csv"

mkdir -p data

echo "Downloading Obras Iniciadas..."
curl -sS -f -A "osm-bsas-building-import/1.0" -o "$OUTPUT_FILE" "$URL"

if [ ! -s "$OUTPUT_FILE" ]; then
    echo "Error: Failed to fetch Obras Iniciadas or output file is empty"
    exit 1
fi

echo "Obras Iniciadas saved to $OUTPUT_FILE ($(($(wc -l < "$OUTPUT_FILE") - 1)) works)"
