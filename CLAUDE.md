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

### Key Components

#### Database Tables
- `city_data`: Raw Buenos Aires building data imported from GeoJSON
- `live_buildings`: Current OSM building data
- `non_intersecting`: Final cleaned buildings ready for import (created by migrations)

#### Migration Pipeline (`migrations/`)
SQL files executed in numerical order:
- `010-remove-columns.sql`: Remove unnecessary columns from source data
- `020-remove-tiny-geoms.sql`: Filter out geometries below minimum size
- `030-remove-duplicate-ids.sql`: Handle duplicate SMP identifiers
- `040-clean-up-outlier-smps.sql`: Remove outlier building codes
- `050-split-smp-columns.sql`: Parse SMP codes into structured columns
- `060-create-indexes.sql`: Add spatial and attribute indexes
- `065-remove-repeated-points.sql`: Clean geometry coordinates
- `070-merge-redundant-geoms.sql`: Combine overlapping geometries
- `080-cut-out-nested-geoms.sql`: Handle nested building geometries
- `090-simplify-geoms.sql`: Simplify geometry for better performance
- `110-remove-live-intersections.sql`: Exclude buildings that intersect with existing OSM data
- `500-create-changefiles.py`: Generate OSM changeset files

#### Changeset Generation
- Creates OSM XML changeset files with negative IDs for new objects
- Groups buildings by city blocks ("manzanas") with 5 manzanas per file
- Handles both simple ways and multipolygon relations for complex geometries
- Includes building tags: `building=yes`, `smp=<code>`, `height=<value>`

### Key Concepts

#### SMP Codes
- Unique identifiers from Buenos Aires cadastral system
- Format: `seccion-manzana-parcela` (e.g., "13-123-456")
- Buildings with same SMP but multiple geometries become multipolygon relations

#### Geometry Processing
- Uses PostGIS for spatial operations and transformations
- Handles coordinate system conversions (city data → WGS84 for OSM)
- Processes both simple polygons and multipolygon geometries
- Implements data cleaning to remove artifacts and duplicates

## Dependencies

- Docker Compose (for PostgreSQL/PostGIS database)
- Python 3.12+ with uv package manager
- GDAL/ogr2ogr for GeoJSON import
- psycopg2-binary and shapely (Python dependencies for changeset generation)

## File Structure

- `bin/`: Shell scripts for common operations
- `data/`: Input GeoJSON files (not version controlled)
- `migrations/`: SQL transformation scripts and Python changeset generator
- `changesets/`: Output OSM changeset files
- `examples/`: Example GeoJSON files demonstrating processing issues