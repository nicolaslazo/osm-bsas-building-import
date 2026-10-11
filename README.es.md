# Importación de Datos de OpenStreetMap para la Ciudad de Buenos Aires

![PostgreSQL](https://img.shields.io/badge/PostgreSQL-316192?style=flat-square&logo=postgresql&logoColor=white)
![PostGIS](https://img.shields.io/badge/PostGIS-4169E1?style=flat-square&logo=postgresql&logoColor=white)
![Python](https://img.shields.io/badge/Python-3776AB?style=flat-square&logo=python&logoColor=white)
![OSM](https://img.shields.io/badge/OpenStreetMap-7EBC6F?style=flat-square&logo=openstreetmap&logoColor=white)
[![English](https://img.shields.io/badge/English-Original-blue?style=flat-square&logo=english&logoColor=white)](README.md)

Un conjunto de herramientas para importar, limpiar y
procesar datos de edificios de Buenos Aires desde
fuentes oficiales del gobierno de la ciudad a un formato compatible con OpenStreetMap.

## Contexto y Propósito

Este proyecto conecta los datos oficiales de edificios de Buenos Aires
con OpenStreetMap mediante:

- El uso de geometrías y atributos de datasets autorizados de la ciudad
- La referencia cruzada con datos en vivo de OSM para evitar conflictos
- La limpieza y transformación de datos a través de migraciones SQL
- La generación de conjuntos de resultados: archivos New por sección, Conflicts por manzana y tareas Reshape

## Estructura del Proyecto

- `bin/` - Scripts auxiliares:
  - `download-dataset.sh` - Descarga el dataset de tejido urbano de Buenos Aires
  - `fetch-live.sh` - Descarga los edificios de OSM en vivo, con metadatos, desde Overpass
  - `import-datasets.sh` - Importa datos de la ciudad y OSM en PostgreSQL/PostGIS
  - `run-migrations.sql` - Ejecuta scripts de migración SQL
  para la transformación de datos
  - `export-geojson.sh` - Exporta resultados de consultas como GeoJSON para debugging
- `examples/` - Archivos GeoJSON de ejemplo para algunos de los problemas abordados
- `migrations/` - Scripts SQL y Python para transformación de datos
- `changesets/` - Directorio de salida para los archivos de cambios de OSM generados

## Primeros Pasos

### 1. Descargar Datasets

```sh
bin/download-dataset.sh   # dataset de la ciudad, data/tejido-<fecha>.geojson y su .source (etiqueta source de los changesets)
bin/fetch-live.sh         # descarga de OSM en vivo desde Overpass, data/live-osm-<fecha>.osm
```

### 2. Importar Datasets a PostgreSQL/PostGIS

Iniciá la base de datos:

```sh
docker compose up -d
```

Importá los datasets en un schema, uno por corrida:

```sh
# IMPORT_UID: el uid de OSM de la cuenta de importación, una vez que subió New
TEJIDO=data/tejido-<fecha>.geojson LIVE=data/live-osm-<fecha>.osm bin/import-datasets.sh run_<fecha>
```

### 3. Ejecutar Limpieza, Estructuras y Clasificación

```sh
bin/run-migrations.sql run_<fecha>
```

Cada migración corre en su propia transacción y el script se detiene en el primer error. Dos
controles (102 y 160) detienen la corrida si los conteos de footprints o la clasificación no
cierran.

### 4. Generar los Conjuntos de Resultados

```sh
.venv/bin/python migrations/500-create-changefiles.py run_<fecha> --live data/live-osm-<fecha>.osm
```

La configuración del venv está en el encabezado del script; necesita los bindings de Python de
GDAL del sistema. Los resultados quedan en `changesets/run_<fecha>/`:

- `new/`: estructuras nuevas, un archivo `.osm` por sección
- `conflicts/`: conflictos, un archivo `.osm` por manzana, para revisión
- `reshape/`: un archivo `.osc` por tarea Reshape (grupos Reshape vecinos de una manzana), para
  un desafío cooperativo de MapRoulette

Antes de la siguiente ronda, revisá los nodos viejos que Reshape dejó sin uso (no sube nada):

```sh
python3 migrations/510-clean-up-reshape-orphans.py changesets/run_<fecha>
```

## Requisitos

- Docker Compose para PostgreSQL/PostGIS
- Python 3.12+
- Gestor de paquetes uv (para armar `.venv`)
- GDAL con ogr2ogr

## Visualización

Para visualizar los resultados del procesamiento:

```sh
bin/export-geojson.sh "SELECT * FROM run_<fecha>.structures LIMIT 100" > debug.geojson
```

Podés abrir el archivo en QGIS o cualquier visor de GeoJSON.

## Referencias

- [Dataset de Tejido Urbano de Buenos Aires](https://data.buenosaires.gob.ar/dataset/tejido-urbano)

## Licencia

Este proyecto está licenciado bajo la Licencia MIT -
consulta el archivo [LICENSE](LICENSE.md) para más detalles.

## Contribuciones

Las contribuciones son bienvenidas! No dudes en:

- Informar sobre problemas
- Sugerir mejoras en el proceso de procesamiento
- Agregar nuevas reglas de limpieza de datos
- Mejorar la documentación
