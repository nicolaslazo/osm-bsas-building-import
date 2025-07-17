
DB_CONN="postgresql://osm:password@localhost:6543/osm_db"

# Run all transformation scripts in order
for script in $(ls migrations/*.sql | sort); do
  echo "Running transformation: $script"
  psql $DB_CONN -f $script
  
  # Check for errors
  if [ $? -ne 0 ]; then
    echo "Error running $script"
    exit 1
  fi
done

echo "All transformations completed successfully"
