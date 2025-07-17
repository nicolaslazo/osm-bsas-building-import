# OpenStreetMap Buenos Aires City Dataset Import

This project provides tools and scripts to import, clean, and process the Buenos Aires city building dataset provided by the government for spatial analysis and OSM changefile generation.

## Project Structure

- `bin/`
  - `download-live-osm-data.sh`: Downloads live OSM building data for Buenos Aires using Overpass API.
  - `import-datasets.sh`: Imports both the city dataset and live OSM buildings into PostgreSQL/PostGIS.
  - `run-migrations.sql`: Runs all SQL migration scripts in order to clean and transform the imported data.
  - `export-geojson.sh`: Debugging tool to write the output of a PostGIS query as a GeoJSON file.
- `migrations/`: The SQL and Python scripts meant to transform both datasets into the resulting changefiles.
- `changesets/`: The project's output directory.

## Context & Purpose

- The city dataset provides authoritative building geometries and attributes for Buenos Aires.
- Live OSM data is used to identify and exclude buildings already mapped in OSM.
- The migration scripts clean, deduplicate, and spatially process the city dataset for compatibility with OSM.
- The final Python script generates OSM changefiles for import, chunked by city block (or as named in the dataset, manzana).

## Instructions

1. **Download the City Dataset**
   - Visit [Buenos Aires Urban Fabric Dataset](https://data.buenosaires.gob.ar/dataset/tejido-urbano) and download the GeoJSON file. Place it as `data/dataset.geojson`.

2. **Download Live OSM Data**
   - Run:
     ```sh
     bin/download-live-osm-data.sh
     ```
   - Output will be saved as `data/live-osm-data.geojson`.

3. **Import Datasets into PostgreSQL/PostGIS**
   - Ensure PostgreSQL is running and PostGIS is enabled.
     ```sh
     docker compose up -d
     ```
   - Run:
     ```sh
     bin/import-datasets.sh
     ```
   - This will import both datasets into tables `city_data` and `live_buildings`.

4. **Run Data Cleaning and Transformation Migrations**
   - Run:
     ```sh
     bin/run-migrations.sql
     ```

5. **Generate OSM Changefiles**
   - Run:
     ```sh
     uv run migrations/500-create-changefiles.py
     ```
   - Changefiles will be generated in the `changesets/` directory.

## Requirements
- Docker Compose
- Python 3.12+
- uv
- `ogr2ogr` (GDAL)

---

For questions or issues, please open an issue in this repository.
