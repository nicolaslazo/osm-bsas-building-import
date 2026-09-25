# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Overview

This project processes Buenos Aires building data from official government sources to create OpenStreetMap-compatible changefiles. It uses PostgreSQL/PostGIS for data transformation and generates OSM changeset files for importing buildings into OSM.

## Common Development Commands

### Database Setup
- Start PostgreSQL/PostGIS: `docker compose up -d`
- Database runs on port 6543 with credentials: `osm:password@localhost:6543/osm_db`

### Data Pipeline
1. Download datasets: `bin/download-dataset.sh` (downloads city data; OSM data must be obtained manually via Overpass Turbo)
2. Import datasets: `bin/import-datasets.sh`
3. Run transformations: `bin/run-migrations.sql`
4. Generate changefiles: `uv run migrations/500-create-changefiles.py`

### Debugging and Development
- Export query results as GeoJSON: `bin/export-geojson.sh "SQL_QUERY" > output.geojson`
- Connect to database: `bin/dpsql.sh` (if available)
- Run shell in container: `bin/dshell.sh` (if available)

## Architecture

### Data Flow
1. **Input**: Two GeoJSON datasets
   - `data/tejido.geojson`: Buenos Aires city building dataset
   - `data/live-osm-data.geojson`: Current OSM building data
2. **Processing**: Sequential SQL migrations transform and clean data
3. **Output**: OSM changeset files in `changesets/` directory
