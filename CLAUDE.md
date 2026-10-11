# CLAUDE.md

## Overview

This project processes Buenos Aires building data from official government sources to create OpenStreetMap-compatible changefiles. It uses PostgreSQL/PostGIS for data transformation and generates OSM changeset files for importing buildings into OSM.

## Common Development Commands

### Database Setup
- Start PostgreSQL/PostGIS: `docker compose up -d`
- Database runs on port 6543 with credentials: `osm:password@localhost:6543/osm_db`

### Data Pipeline
1. Download datasets: `bin/download-dataset.sh` (city data, `data/tejido-<date>.geojson` plus its `.source` file, the changeset source tag) and `bin/fetch-live.sh` (Live OSM fetch, `data/live-osm-<date>.osm`)
2. Import datasets: `TEJIDO=... LIVE=... IMPORT_UID=... bin/import-datasets.sh <schema>` (`IMPORT_UID` is the import account's OSM uid; leave it unset until that account has uploaded)
3. Run transformations: `bin/run-migrations.sql [schema]` (runs `migrations/*.sql` in numeric order; stops at the first error)
4. Generate result sets: `.venv/bin/python migrations/500-create-changefiles.py <schema>` (writes `changesets/<schema>/`; venv setup in the script header, it needs the system GDAL bindings)
5. Before the next release round: `python3 migrations/510-clean-up-reshape-orphans.py changesets/<schema>` (checks the old nodes Reshape left unused and writes their deletion; uploads nothing)

### Debugging and Development
- Export query results as GeoJSON: `bin/export-geojson.sh "SQL_QUERY" [output.geojson]` (writes `output.geojson` by default; don't redirect stdout)
- Connect to database: `bin/dpsql.sh` (psql in the `osm_postgis` container)
- Run shell in container: `bin/dshell.sh`

## Architecture

### Data Flow
1. **Input**: Two datasets
   - `data/tejido-<date>.geojson`: Buenos Aires city building dataset
   - `data/live-osm-<date>.osm`: the Live OSM fetch
2. **Processing**: Sequential SQL migrations transform and clean data; 170 groups neighbouring Reshape groups into Reshape tasks
3. **Output**: result sets in `changesets/<schema>/`: New files per seccion, Conflicts files per block, one Reshape `.osc` per Reshape task
