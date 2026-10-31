#!/bin/bash
# Usage: bin/import-datasets.sh [schema]
#   TEJIDO=data/tejido-YYYY-MM-DD.geojson LIVE=data/live-osm-YYYY-MM-DD.osm OBRAS=data/obras-iniciadas-YYYY-MM-DD.csv IMPORT_UID=N bin/import-datasets.sh run_x
# Loads city_data, live_buildings, live_at_cutoff and building_works into the schema (default
# public), replacing them. TEJIDO needs its .source file beside it (bin/download-dataset.sh),
# LIVE its .cutoff file (bin/fetch-live.sh); OBRAS comes from bin/download-obras.sh.

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
CUTOFF_FILE="${LIVE%.osm}.cutoff"
if [ ! -s "${CUTOFF_FILE}" ]; then
    echo "Error: ${CUTOFF_FILE} is missing; bin/fetch-live.sh writes it" >&2
    exit 1
fi
OBRAS="${OBRAS:-$(ls "${DATA_DIR}"/obras-iniciadas-*.csv | sort | tail -1)}"
OBRAS_HEADER="periodo,long,lat,exp_dgroc,calle,callenro,seccion,manzana,parcela,fecha_inicio_obra,estado,ultimo_avo_solicitado,fecha_ultimo_avo,estadotramite,profesional,metrosaconstruir,fecha_estado_tramite,tipo_obra,destino,barrios,comuna,codigo_postal,codigo_postal_argentino"
if [ "$(head -1 "${OBRAS}" | tr -d '\r\357\273\277' | tr 'A-Z' 'a-z')" != "${OBRAS_HEADER}" ]; then
    echo "Error: ${OBRAS} does not have the expected columns" >&2
    exit 1
fi
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

# The data date (PLAN 4.9, 4.10), from the changeset source tag; the cutoff of 127
PGPASSWORD=password psql -h localhost -p 6543 -U osm osm_db -q -v ON_ERROR_STOP=1 <<SQL
DROP TABLE IF EXISTS "${SCHEMA}".data_date;
CREATE TABLE "${SCHEMA}".data_date AS
SELECT substring(tag FROM ', ([0-9-]+)\)$')::DATE AS cutoff FROM "${SCHEMA}".changeset_source;
SQL

# Ways and relations tagged building=* at the data date (PLAN 4.9), from the .cutoff file
PGPASSWORD=password psql -h localhost -p 6543 -U osm osm_db -q -v ON_ERROR_STOP=1 <<SQL
DROP TABLE IF EXISTS "${SCHEMA}".live_at_cutoff;
CREATE TABLE "${SCHEMA}".live_at_cutoff (type TEXT NOT NULL, id BIGINT NOT NULL, PRIMARY KEY (type, id));
SQL
PGPASSWORD=password psql -h localhost -p 6543 -U osm osm_db -q -v ON_ERROR_STOP=1 \
    -c "\\copy \"${SCHEMA}\".live_at_cutoff FROM '${CUTOFF_FILE}'"

# Building works started in the city (PLAN 4.10), as delivered; 127 reads the SMP and date
PGPASSWORD=password psql -h localhost -p 6543 -U osm osm_db -q -v ON_ERROR_STOP=1 <<SQL
DROP TABLE IF EXISTS "${SCHEMA}".building_works;
CREATE TABLE "${SCHEMA}".building_works ($(echo "${OBRAS_HEADER}" | sed 's/,/ TEXT, /g') TEXT);
SQL
PGPASSWORD=password psql -h localhost -p 6543 -U osm osm_db -q -v ON_ERROR_STOP=1 \
    -c "\\copy \"${SCHEMA}\".building_works FROM '${OBRAS}' WITH (FORMAT csv, HEADER true)"
