#!/bin/bash

PROJECT_ROOT="$(dirname "$(realpath "$0")")"
DATA_DIR="${PROJECT_ROOT}/data"

ogr2ogr \
  -f "PostgreSQL" \
  PG:"host=localhost port=6543 dbname=osm_db user=osm password=password" \
  -nln city_data \
  -nlt PROMOTE_TO_MULTI \
  -lco GEOMETRY_NAME=geom \
  -lco FID=ogr_fid \
  -lco SPATIAL_INDEX=GIST \
  "GeoJSONSeq:${DATA_DIR}/tejido.geojson"

ogr2ogr \
  -f "PostgreSQL" \
  PG:"host=localhost port=6543 dbname=osm_db user=osm password=password" \
  -nln live_buildings \
  -nlt PROMOTE_TO_MULTI \
  -lco GEOMETRY_NAME=geom \
  -lco FID=ogr_fid \
  -lco SPATIAL_INDEX=GIST \
  "GeoJSONSeq:${DATA_DIR}/live-buildings.geojson"
