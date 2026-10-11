#!/bin/bash
# Downloads Tejido Urbano to data/tejido-<download date>.geojson and writes beside it, in
# data/tejido-<download date>.source, the changeset source tag (PLAN 6.9). The date in the tag
# is the file's Last-Modified on the CDN, when the city last changed the data; the portal's
# "Fecha de actualización" moves with metadata edits alone.

set -e

URL="https://cdn.buenosaires.gob.ar/datosabiertos/datasets/secretaria-de-desarrollo-urbano/tejido-urbano/tejido.geojson"
# The portal's firewall rejects curl's default user agent
UA="Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/128.0 Safari/537.36"
OUTPUT_FILE_TEJIDO="data/tejido-$(date +%F).geojson"

mkdir -p data

echo "Downloading Tejido Urbano dataset..."
HEADERS=$(curl -sS -f -A "$UA" -D - -o "$OUTPUT_FILE_TEJIDO" "$URL")

if [ ! -s "$OUTPUT_FILE_TEJIDO" ]; then
    echo "Error: Failed to fetch Tejido Urbano dataset or output file is empty"
    exit 1
fi

LAST_MODIFIED=$(printf '%s\n' "$HEADERS" | tr -d '\r' | sed -n 's/^[Ll]ast-[Mm]odified: //p' | tail -1)
if [ -z "$LAST_MODIFIED" ]; then
    echo "Error: the server sent no Last-Modified date"
    exit 1
fi
DATA_DATE=$(date -u -d "$LAST_MODIFIED" +%F)
echo "Buenos Aires - Tejido Urbano (data.buenosaires.gob.ar, ${DATA_DATE})" > "${OUTPUT_FILE_TEJIDO%.geojson}.source"

echo "Tejido Urbano dataset successfully saved to $OUTPUT_FILE_TEJIDO (data of ${DATA_DATE})"
