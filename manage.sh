#!/bin/bash
# OSM Tile Server Management Script

set -e

CMD="$1"

show_help() {
    cat << EOF
OSM Tile Server Management Script

Usage: ./manage.sh <command>

Commands:
    start              Start all services
    stop               Stop all services
    restart            Restart all services
    logs               Show logs (follow mode)
    status             Show container status
    import <file>      Import OSM data from file
    download <url> [--import] [--cache <mb>] [--threads <n>]
                       Download OSM data from URL
                       --import: Automatically import after download
                       --cache: Memory cache for import in MB (default: 2048)
                       --threads: Number of parallel threads (default: 4)
    clean-tiles        Clear tile cache
    clean-all          Stop and remove all data (WARNING: deletes everything)
    shell              Open shell in tile-server container
    db-shell           Open PostgreSQL shell
    rebuild            Rebuild containers (useful after config changes)

Examples:
    ./manage.sh start
    ./manage.sh logs
    ./manage.sh download https://download.geofabrik.de/north-america/canada-latest.osm.pbf --import
    ./manage.sh download https://download.geofabrik.de/north-america/canada-latest.osm.pbf --import --cache 4096 --threads 8
    ./manage.sh import /data/my-region.osm.pbf
    ./manage.sh clean-tiles

EOF
}

case "$CMD" in
    start)
        echo "Starting OSM tile server..."
        docker-compose up -d
        echo "Services started! Access at http://localhost"
        ;;

    stop)
        echo "Stopping OSM tile server..."
        docker-compose down
        echo "Services stopped."
        ;;

    restart)
        echo "Restarting OSM tile server..."
        docker-compose restart
        echo "Services restarted."
        ;;

    logs)
        docker-compose logs -f
        ;;

    status)
        docker-compose ps
        ;;

    import)
        FILE="$2"
        if [ -z "$FILE" ]; then
            echo "Error: Please specify OSM file path"
            echo "Usage: ./manage.sh import <file-path>"
            exit 1
        fi
        echo "Importing OSM data from $FILE..."
        docker-compose exec tile-server /usr/local/bin/import-osm.sh "$FILE"
        ;;

    download)
        URL="$2"
        if [ -z "$URL" ]; then
            echo "Error: Please specify download URL"
            echo "Usage: ./manage.sh download <url> [--import] [--cache <mb>] [--threads <n>]"
            exit 1
        fi

        # Parse optional flags
        SHOULD_IMPORT=false
        CACHE_SIZE=2048
        THREADS=4
        shift 2

        while [[ $# -gt 0 ]]; do
            case "$1" in
                --import)
                    SHOULD_IMPORT=true
                    shift
                    ;;
                --cache)
                    CACHE_SIZE="$2"
                    shift 2
                    ;;
                --threads)
                    THREADS="$2"
                    shift 2
                    ;;
                *)
                    echo "Unknown option: $1"
                    exit 1
                    ;;
            esac
        done

        # Create data directory if it doesn't exist
        DATA_DIR="./osm-data"
        mkdir -p "$DATA_DIR"

        # Extract filename from URL
        FILENAME=$(basename "$URL")

        echo "========================================"
        echo "OSM Data Download"
        echo "========================================"
        echo "Region URL: $URL"
        echo "Filename: $FILENAME"
        if [ "$SHOULD_IMPORT" = true ]; then
            echo "Auto-import: Yes"
            echo "Cache size: ${CACHE_SIZE}MB"
            echo "Threads: $THREADS"
        fi
        echo "========================================"

        # Download the file
        if [ -f "$DATA_DIR/$FILENAME" ]; then
            echo "File already exists. Skipping download."
            read -p "Do you want to re-download? (y/N): " -n 1 -r
            echo
            if [[ $REPLY =~ ^[Yy]$ ]]; then
                echo "Downloading $FILENAME..."
                wget -O "$DATA_DIR/$FILENAME" "$URL"
            fi
        else
            echo "Downloading $FILENAME..."
            wget -O "$DATA_DIR/$FILENAME" "$URL"
        fi

        echo "Download complete!"

        # Import if requested
        if [ "$SHOULD_IMPORT" = true ]; then
            echo "Starting Docker containers..."
            docker-compose up -d

            echo "Waiting for services to start..."
            sleep 10

            echo "Starting import process..."
            echo "This may take a while depending on the size of the data..."

            docker-compose exec -T tile-server bash -c "
                export OSM_IMPORT_CACHE=$CACHE_SIZE
                export THREADS=$THREADS
                /usr/local/bin/import-osm.sh /data/$FILENAME
            "

            echo "========================================"
            echo "Import complete!"
            echo "========================================"
            echo "Your tile server is now ready!"
            echo "Access it at: http://localhost"
            echo ""
            echo "To view logs: docker-compose logs -f tile-server"
            echo "========================================"
        else
            echo "File downloaded to: $DATA_DIR/$FILENAME"
            echo "To import, run: ./manage.sh import /data/$FILENAME"
        fi
        ;;

    clean-tiles)
        echo "Clearing tile cache..."
        docker-compose exec tile-server rm -rf /var/lib/mod_tile/*
        docker-compose restart tile-server
        echo "Tile cache cleared and server restarted."
        ;;

    clean-all)
        echo "WARNING: This will delete all data including the database!"
        read -p "Are you sure? (type 'yes' to confirm): " confirm
        if [ "$confirm" = "yes" ]; then
            docker-compose down -v
            rm -rf osm-data/
            echo "All data removed."
        else
            echo "Aborted."
        fi
        ;;

    shell)
        docker-compose exec tile-server bash
        ;;

    db-shell)
        docker-compose exec postgres psql -U renderaccount -d gis
        ;;

    rebuild)
        echo "Rebuilding containers..."
        docker-compose build --no-cache
        docker-compose up -d
        echo "Rebuild complete."
        ;;

    help|--help|-h|"")
        show_help
        ;;

    *)
        echo "Unknown command: $CMD"
        echo ""
        show_help
        exit 1
        ;;
esac
