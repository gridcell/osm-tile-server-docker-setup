#!/bin/bash
set -e

echo "Starting OSM Tile Server..."

# Create necessary runtime directories
mkdir -p /run/renderd
chown renderer:renderer /run/renderd
mkdir -p /var/run/apache2
mkdir -p /var/log/apache2
mkdir -p /var/lock/apache2

# Wait for PostgreSQL to be ready
until PGPASSWORD=renderpassword psql -h postgres -U renderaccount -d gis -c '\q' 2>/dev/null; do
    echo "Waiting for PostgreSQL to be ready..."
    sleep 2
done

echo "PostgreSQL is ready!"

# Install required SQL functions if not already installed
FUNCTION_EXISTS=$(PGPASSWORD=renderpassword psql -h postgres -U renderaccount -d gis -t -c "SELECT COUNT(*) FROM pg_proc WHERE proname = 'carto_path_type';")
if [ "$FUNCTION_EXISTS" -eq 0 ]; then
    echo "Installing required SQL functions..."
    PGPASSWORD=renderpassword psql -h postgres -U renderaccount -d gis -f /home/renderer/src/openstreetmap-carto/functions.sql
    echo "SQL functions installed successfully!"
else
    echo "SQL functions already installed."
fi

# Download external data (shapefiles) if not already present
EXT_DATA_EXISTS=$(PGPASSWORD=renderpassword psql -h postgres -U renderaccount -d gis -t -c "SELECT COUNT(*) FROM information_schema.tables WHERE table_name = 'icesheet_polygons';")
if [ "$EXT_DATA_EXISTS" -eq 0 ]; then
    echo "========================================"
    echo "Downloading external data (shapefiles)..."
    echo "This may take several minutes..."
    echo "========================================"
    cd /home/renderer/src/openstreetmap-carto
    sudo -u renderer bash -c "export PGHOST=postgres PGPORT=5432 PGDATABASE=gis PGUSER=renderaccount PGPASSWORD=renderpassword && python3 scripts/get-external-data.py"
    echo "External data downloaded and imported successfully!"
else
    echo "External data already imported."
fi

# Check if data has been imported
TABLE_COUNT=$(PGPASSWORD=renderpassword psql -h postgres -U renderaccount -d gis -t -c "SELECT COUNT(*) FROM information_schema.tables WHERE table_name LIKE 'planet_osm%';")

if [ "$TABLE_COUNT" -lt 4 ]; then
    echo "========================================"
    echo "WARNING: OSM data not imported yet!"
    echo "========================================"
    echo "To import data, run:"
    echo "  docker-compose exec tile-server import-osm.sh /data/your-map.osm.pbf"
    echo ""
    echo "Or use the download-and-import.sh script to automatically download and import data"
    echo "========================================"
else
    echo "OSM data found in database. Ready to serve tiles!"
fi

# Start renderd as renderer user
echo "Starting renderd..."
sudo -u renderer renderd -f -c /etc/renderd.conf &

# Wait a bit for renderd to start
sleep 3

# Start Apache
echo "Starting Apache web server..."
. /etc/apache2/envvars
apache2 -D FOREGROUND
