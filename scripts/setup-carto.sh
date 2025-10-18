#!/bin/bash
set -e

# Script to configure and compile openstreetmap-carto with correct database settings

cd /home/renderer/src/openstreetmap-carto

# Update project.mml to use network PostgreSQL connection instead of Unix socket
# Set the database connection parameters
cat > localconfig.json <<EOF
{
  "host": "postgres",
  "port": 5432,
  "dbname": "gis",
  "user": "renderaccount",
  "password": "renderpassword"
}
EOF

# Compile the mapnik XML with the correct database settings
carto -l localconfig.json project.mml > mapnik.xml

echo "Mapnik configuration updated with network database connection"
