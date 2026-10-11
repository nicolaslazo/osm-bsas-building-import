#!/bin/bash
# Usage: bin/import-datasets.sh [schema]
#   TEJIDO=data/tejido-YYYY-MM-DD.geojson LIVE=data/live-osm-YYYY-MM-DD.osm IMPORT_UID=N bin/import-datasets.sh run_x
# Loads city_data and live_buildings into the schema (default public), replacing them.
# TEJIDO needs its .source file beside it (bin/download-dataset.sh).

set -e

PROJECT_ROOT="$(dirname "$(dirname "$(realpath "$0")")")"
DATA_DIR="${PROJECT_ROOT}/data"
SCHEMA="${1:-public}"
TEJIDO="${TEJIDO:-$(ls "${DATA_DIR}"/tejido-*.geojson | sort | tail -1)}"
SOURCE_FILE="${TEJIDO%.geojson}.source"
if [ ! -s "${SOURCE_FILE}" ]; then
    echo "Error: ${SOURCE_FILE} is missing; bin/download-dataset.sh writes it" >&2
    exit 1
fi
LIVE="${LIVE:-$(ls "${DATA_DIR}"/live-osm-*.osm | sort | tail -1)}"
PG="PG:host=localhost port=6543 dbname=osm_db user=osm password=password"

PGPASSWORD=password psql -h localhost -p 6543 -U osm osm_db -qc "CREATE SCHEMA IF NOT EXISTS \"${SCHEMA}\""

ogr2ogr \
  -f "PostgreSQL" "$PG" \
  -overwrite \
  -nln "${SCHEMA}.city_data" \
  -nlt PROMOTE_TO_MULTI \
  -lco GEOMETRY_NAME=geom \
  -lco FID=ogr_fid \
  -lco SPATIAL_INDEX=GIST \
  "${TEJIDO}"

# Footprint count ledger (PLAN 5.1): the source count and the imported count; the migrations
# that remove or add footprints append to it and Gate 1 (102) reconciles it
SOURCE_COUNT=$(ogrinfo -ro -so -al "${TEJIDO}" 2>/dev/null | sed -n 's/^Feature Count: //p')
PGPASSWORD=password psql -h localhost -p 6543 -U osm osm_db -q -v ON_ERROR_STOP=1 <<SQL
DROP TABLE IF EXISTS "${SCHEMA}".footprint_counts;
CREATE TABLE "${SCHEMA}".footprint_counts (
    seq SERIAL PRIMARY KEY, step TEXT NOT NULL,
    removed INT NOT NULL, added INT NOT NULL, total INT NOT NULL);
INSERT INTO "${SCHEMA}".footprint_counts (step, removed, added, total) VALUES
    ('source', 0, 0, ${SOURCE_COUNT}),
    ('import', 0, 0, (SELECT COUNT(*) FROM "${SCHEMA}".city_data));
SQL

# Raw .osm from the live fetch (PLAN 6.2); building and building:part areas only
ogr2ogr \
  -f "PostgreSQL" "$PG" \
  -overwrite \
  --config OSM_CONFIG_FILE "${PROJECT_ROOT}/bin/osmconf-buildings.ini" \
  -where "building IS NOT NULL OR \"building:part\" IS NOT NULL" \
  -nln "${SCHEMA}.live_buildings" \
  -nlt PROMOTE_TO_MULTI \
  -lco GEOMETRY_NAME=geom \
  -lco FID=ogr_fid \
  -lco SPATIAL_INDEX=GIST \
  "${LIVE}" multipolygons

# The import account's OSM uid (PLAN 5.3, 6.7), for 125 to recognise its uploads in Live;
# unset before the account uploads anything
PGPASSWORD=password psql -h localhost -p 6543 -U osm osm_db -q -v ON_ERROR_STOP=1 <<SQL
DROP TABLE IF EXISTS "${SCHEMA}".import_account;
CREATE TABLE "${SCHEMA}".import_account (uid INT PRIMARY KEY);
INSERT INTO "${SCHEMA}".import_account SELECT NULLIF('${IMPORT_UID}', '')::INT WHERE '${IMPORT_UID}' <> '';
SQL

# The changeset source tag (PLAN 6.9), from the .source file of the Tejido download
PGPASSWORD=password psql -h localhost -p 6543 -U osm osm_db -q -v ON_ERROR_STOP=1 -v tag="$(cat "${SOURCE_FILE}")" <<SQL
DROP TABLE IF EXISTS "${SCHEMA}".changeset_source;
CREATE TABLE "${SCHEMA}".changeset_source (tag TEXT NOT NULL);
INSERT INTO "${SCHEMA}".changeset_source VALUES (:'tag');
SQL
