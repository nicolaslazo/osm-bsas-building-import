# OpenStreetMap Buenos Aires City Dataset Import

![PostgreSQL](https://img.shields.io/badge/PostgreSQL-316192?style=flat-square&logo=postgresql&logoColor=white)
![PostGIS](https://img.shields.io/badge/PostGIS-4169E1?style=flat-square&logo=postgresql&logoColor=white)
![Python](https://img.shields.io/badge/Python-3776AB?style=flat-square&logo=python&logoColor=white)
![OSM](https://img.shields.io/badge/OpenStreetMap-7EBC6F?style=flat-square&logo=openstreetmap&logoColor=white)
![Leer en Español](https://img.shields.io/badge/%F0%9F%87%A6%F0%9F%87%B7-Leer_en_Espa%C3%B1ol-6CACE4?style=flat-square&link=README.es.md)

A toolset for importing, cleaning, and processing Buenos Aires building data from
official government sources into OpenStreetMap-compatible format.

## Context & Purpose

This project bridges official Buenos Aires building data with OpenStreetMap by:

- Using authoritative city dataset geometries and attributes
- Cross-referencing with live OSM data to prevent duplicates
- Cleaning and transforming data through SQL migrations
- Generating OSM changefiles chunked by city blocks ("manzanas")

## Project Structure

- `bin/` - Helper scripts:
  - `download-live-osm-data.sh` - Fetches current OSM buildings via Overpass API
  - `import-datasets.sh` - Imports city and OSM data into PostgreSQL/PostGIS
  - `run-migrations.sql` - Executes SQL migration scripts for data transformation
  - `export-geojson.sh` - Exports query results as GeoJSON for debugging
- `migrations/` - SQL and Python scripts for data transformation
- `changesets/` - Output directory for generated OSM changefiles

## Getting Started

### 1. Download Datasets

Run the import script which will download both the city dataset and OSM data:

```sh
bin/import-dataset.sh
```

This script will:

- Download the city dataset from Buenos Aires Urban Fabric Dataset
- Fetch current OSM building data via the Overpass API
- Save files to `data/dataset.geojson` and `data/live-osm-data.geojson`

### 2. Import Datasets into PostgreSQL/PostGIS

Start the database:

```sh
docker compose up -d
```

Import the datasets:

```sh
bin/import-datasets.sh
```

### 3. Run Data Cleaning and Transformation

```sh
bin/run-migrations.sql
```

### 4. Generate OSM Changefiles

```sh
uv run migrations/500-create-changefiles.py
```

Changefiles will be available in the `changesets/` directory, organized by city block.

## Requirements

- Docker Compose for PostgreSQL/PostGIS
- Python 3.12+
- uv package manager
- GDAL with ogr2ogr

## Visualization

To visualize the processing results:

```sh
bin/export-geojson.sh "SELECT * FROM processed_buildings LIMIT 100" > debug.geojson
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
