#!/bin/bash
# Usage: bin/run-migrations.sql [schema]
# Runs every migration in order inside the schema (default public); stops at the first error.

set -e

DB_CONN="postgresql://osm:password@localhost:6543/osm_db"
SCHEMA="${1:-public}"
export PGOPTIONS="-c search_path=${SCHEMA},public -c client_min_messages=notice"

for script in $(ls migrations/*.sql | sort); do
  echo "Running transformation: $script ($(date +%T))"
  if ! psql "$DB_CONN" -X -q -1 -v ON_ERROR_STOP=1 -f "$script"; then
    echo "Error running $script"
    exit 1
  fi
done

echo "All transformations completed successfully"
