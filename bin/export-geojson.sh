#!/bin/bash

# Database connection string
DB_CONN="postgresql://osm:password@localhost:6543/osm_db"

# Default output filename
OUTPUT_FILE="${2:-output.geojson}"

# Function to export query as GeoJSON
export_geojson() {
    local query=$1
    local output=$2
    
    echo "Exporting query to $output..."
    
    # Use ST_AsGeoJSON to convert to GeoJSON collection
    psql $DB_CONN -t -c "
    SELECT jsonb_build_object(
        'type',     'FeatureCollection',
        'features', jsonb_agg(features.feature)
    )
    FROM (
        SELECT jsonb_build_object(
            'type',       'Feature',
            'geometry',   ST_AsGeoJSON(geom)::jsonb,
            'properties', to_jsonb(row) - 'geom'
        ) AS feature
        FROM ($query) row
    ) features;" > "$output"
    
    echo "Export complete: $output"
}

# Example usage:
# ./export-geojson.sh "SELECT * FROM non_intersecting LIMIT 1000" my_export.geojson
export_geojson "$1" "$OUTPUT_FILE"
