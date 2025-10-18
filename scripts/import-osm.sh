#!/bin/bash
set -e

OSM_FILE="${1:-/data/map.osm.pbf}"
CACHE="${OSM_IMPORT_CACHE:-2048}"
THREADS="${THREADS:-4}"
DATABASE_URL="${DATABASE_URL:-postgresql://renderaccount:renderpassword@postgres:5432/gis}"

echo "Starting OSM data import..."
echo "File: $OSM_FILE"
echo "Cache: ${CACHE}MB"
echo "Threads: $THREADS"

if [ ! -f "$OSM_FILE" ]; then
    echo "Error: OSM file not found at $OSM_FILE"
    echo "Please download an OSM extract and place it in the /data directory"
    exit 1
fi

# Wait for PostgreSQL to be ready
until PGPASSWORD=renderpassword psql -h postgres -U renderaccount -d gis -c '\q'; do
    echo "Waiting for PostgreSQL to be ready..."
    sleep 2
done

echo "PostgreSQL is ready. Starting import..."

# Import OSM data with osm2pgsql using flex output
# Set PostgreSQL password for connection
export PGPASSWORD=renderpassword

osm2pgsql \
    --create \
    --slim \
    --drop \
    --cache $CACHE \
    --number-processes $THREADS \
    --database gis \
    --user renderaccount \
    --host postgres \
    --port 5432 \
    --output flex \
    --style /home/renderer/src/openstreetmap-carto/openstreetmap-carto-flex.lua \
    "$OSM_FILE"

echo "OSM data import completed successfully!"

# Create indexes for better performance
echo "Creating indexes..."
PGPASSWORD=renderpassword psql -h postgres -U renderaccount -d gis <<-EOSQL
    CREATE INDEX IF NOT EXISTS idx_planet_osm_point_way ON planet_osm_point USING GIST (way);
    CREATE INDEX IF NOT EXISTS idx_planet_osm_line_way ON planet_osm_line USING GIST (way);
    CREATE INDEX IF NOT EXISTS idx_planet_osm_roads_way ON planet_osm_roads USING GIST (way);
    CREATE INDEX IF NOT EXISTS idx_planet_osm_polygon_way ON planet_osm_polygon USING GIST (way);
EOSQL

echo "Indexes created successfully!"
echo "Import process complete. You can now start rendering tiles."
