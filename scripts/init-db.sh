#!/bin/bash
set -e

# This script runs during PostgreSQL initialization

echo "Initializing OSM database..."

# Create the renderaccount user if not exists
psql -v ON_ERROR_STOP=0 --username "$POSTGRES_USER" --dbname "$POSTGRES_DB" <<-EOSQL
    DO
    \$\$
    BEGIN
        CREATE USER renderaccount WITH PASSWORD 'renderpassword';
    EXCEPTION WHEN duplicate_object THEN
        RAISE NOTICE 'User renderaccount already exists';
    END
    \$\$;
    GRANT ALL PRIVILEGES ON DATABASE gis TO renderaccount;
    ALTER USER renderaccount WITH SUPERUSER;
EOSQL

# Enable PostGIS extensions
psql -v ON_ERROR_STOP=1 --username "$POSTGRES_USER" --dbname "gis" <<-EOSQL
    CREATE EXTENSION IF NOT EXISTS postgis;
    CREATE EXTENSION IF NOT EXISTS hstore;
    ALTER TABLE geometry_columns OWNER TO renderaccount;
    ALTER TABLE spatial_ref_sys OWNER TO renderaccount;
EOSQL

echo "Database initialization complete!"
