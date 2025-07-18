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
- La generación de archivos de cambios de OSM agrupados por manzanas

## Estructura del Proyecto

- `bin/` - Scripts auxiliares:
  - `download-dataset.sh` - Descarga el dataset de tejido urbano de Buenos Aires
  a través de la API de Overpass
  - `import-datasets.sh` - Importa datos de la ciudad y OSM en PostgreSQL/PostGIS
  - `run-migrations.sql` - Ejecuta scripts de migración SQL
  para la transformación de datos
  - `export-geojson.sh` - Exporta resultados de consultas como GeoJSON para debugging
- `migrations/` - Scripts SQL y Python para transformación de datos
- `changesets/` - Directorio de salida para los archivos de cambios de OSM generados

## Primeros Pasos

### 1. Descargar Dataset

1. Visitá [Overpass Turbo](https://overpass-turbo.eu/)
2. Pegá la siguiente consulta:

   ```
   [out:json][timeout:900];
   area["name"="Buenos Aires"]["boundary"="administrative"]["admin_level"="8"]->.searchArea;
   (
     way["building"](area.searchArea);
     relation["building"](area.searchArea);
   );
   out body;
   >;
   out skel qt;
   ```

3. Ejecutá la consulta, después usá Exportar > GeoJSON para guardar como `data/live-osm-data.geojson`
4. Corré el script de descarga del dataset::

```sh
bin/download-dataset.sh
```

Los contenidos se van a descargar en `data/tejido.geojson`.

### 2. Importar Datasets a PostgreSQL/PostGIS

Iniciá la base de datos:

```sh
docker compose up -d
```

Importá los datasets:

```sh
bin/import-datasets.sh
```

### 3. Ejecutar Limpieza y Transformación de Datos

```sh
bin/run-migrations.sql
```

### 4. Generar Archivos de Cambios de OSM

```sh
uv run migrations/500-create-changefiles.py
```

Los archivos de cambios estarán disponibles en el directorio `changesets/`,
organizados en grupos de manzanas.

## Requisitos

- Docker Compose para PostgreSQL/PostGIS
- Python 3.12+
- Gestor de paquetes uv
- GDAL con ogr2ogr

## Visualización

Para visualizar los resultados del procesamiento:

```sh
bin/export-geojson.sh "SELECT * FROM processed_buildings LIMIT 100" > debug.geojson
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
