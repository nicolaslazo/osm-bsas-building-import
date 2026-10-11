# OpenStreetMap Buenos Aires City Dataset Import

![PostgreSQL](https://img.shields.io/badge/PostgreSQL-316192?style=flat-square&logo=postgresql&logoColor=white)
![PostGIS](https://img.shields.io/badge/PostGIS-4169E1?style=flat-square&logo=postgresql&logoColor=white)
![Python](https://img.shields.io/badge/Python-3776AB?style=flat-square&logo=python&logoColor=white)
![OSM](https://img.shields.io/badge/OpenStreetMap-7EBC6F?style=flat-square&logo=openstreetmap&logoColor=white)
[![Leer en Español](https://img.shields.io/badge/%F0%9F%87%A6%F0%9F%87%B7-Leer_en_Espa%C3%B1ol-6CACE4?style=flat-square)](README.es.md)

A toolset for importing, cleaning, and processing Buenos Aires building data from
official government sources into OpenStreetMap-compatible format.

## Context & Purpose

This project bridges official Buenos Aires building data with OpenStreetMap by:

- Using authoritative city dataset geometries and attributes
- Cross-referencing with live OSM data to prevent duplicates
- Cleaning and transforming data through SQL migrations
- Generating result sets: New files per seccion, Conflicts files per block, Reshape tasks

## Project Structure

- `bin/` - Helper scripts:
  - `download-dataset.sh` - Fetches the Buenos Aires urban fabric dataset
  - `fetch-live.sh` - Fetches Live OSM buildings with metadata from Overpass
  - `import-datasets.sh` - Imports city and OSM data into PostgreSQL/PostGIS
  - `run-migrations.sql` - Executes SQL migration scripts for data transformation
  - `export-geojson.sh` - Exports query results as GeoJSON for debugging
- `examples/` - Example GeoJSON files for some of the addressed issues
- `migrations/` - SQL and Python scripts for data transformation
- `changesets/` - Output directory for generated OSM changefiles

## Getting Started

### 1. Download Datasets

```sh
bin/download-dataset.sh   # city dataset, data/tejido-<date>.geojson and its .source (changeset source tag)
bin/fetch-live.sh         # Live OSM fetch from Overpass, data/live-osm-<date>.osm
```

### 2. Import Datasets into PostgreSQL/PostGIS

Start the database:

```sh
docker compose up -d
```

Import the datasets into a schema, one per run:

```sh
# IMPORT_UID: the import account's OSM uid, once it has uploaded New
TEJIDO=data/tejido-<date>.geojson LIVE=data/live-osm-<date>.osm bin/import-datasets.sh run_<date>
```

### 3. Run Data Cleaning, Structures and Classification

```sh
bin/run-migrations.sql run_<date>
```

Each migration runs in its own transaction and the runner stops at the first error. Two gates
(102 and 160) stop the run when the footprint counts or the classification do not reconcile.

### 4. Generate the Result Sets

```sh
.venv/bin/python migrations/500-create-changefiles.py run_<date> --live data/live-osm-<date>.osm
```

The venv setup is in the script header; it needs the system GDAL Python bindings. The result
sets go to `changesets/run_<date>/`:

- `new/`: New structures, one `.osm` file per seccion
- `conflicts/`: Conflicts, one `.osm` file per block, for review
- `reshape/`: one `.osc` file per Reshape task (neighbouring Reshape groups of one block), for a
  MapRoulette cooperative challenge

Before the next release round, check the old nodes Reshape left unused (uploads nothing):

```sh
python3 migrations/510-clean-up-reshape-orphans.py changesets/run_<date>
```

## Requirements

- Docker Compose for PostgreSQL/PostGIS
- Python 3.12+
- uv package manager (to set up `.venv`)
- GDAL with ogr2ogr

## Visualization

To visualize the processing results:

```sh
bin/export-geojson.sh "SELECT * FROM run_<date>.structures LIMIT 100" > debug.geojson
```

Then open the file in QGIS or any GeoJSON viewer.

## References

- [Buenos Aires Urban Fabric Dataset](https://data.buenosaires.gob.ar/dataset/tejido-urbano)

## License

This project is licensed under the MIT License -
see the [LICENSE](LICENSE.md) file for details.

## Contributing

Contributions are welcome! Feel free to:

- Report issues
- Suggest improvements to the processing pipeline
- Add new data cleaning rules
- Enhance documentation
