# OSM Tile Server - Docker Setup

A Dockerized OpenStreetMap tile server based on the [Switch2OSM guide for Ubuntu 24.04](https://switch2osm.org/serving-tiles/manually-building-a-tile-server-ubuntu-24-04-lts/).

This setup provides a complete tile server stack including:
- **PostgreSQL with PostGIS** - Spatial database for OSM data
- **osm2pgsql** - Tool to import OSM data into PostgreSQL
- **Mapnik** - Map rendering engine
- **mod_tile** - Apache module for serving tiles
- **renderd** - Tile rendering daemon
- **OpenStreetMap Carto** - Default OSM map stylesheet

## Prerequisites

- Docker
- Docker Compose
- At least 4GB RAM (8GB+ recommended for larger regions)
- Sufficient disk space for your region (varies greatly by size)

## Quick Start

### 1. Clone or navigate to this directory

```bash
git clone https://github.com/gridcell/osm-tile-server-docker-setup.git
cd osm-tile-server-docker-setup
```

### 2. Download and import OSM data

Use the management script to download and import regions:

```bash
./manage.sh download <region-url> --import [cache-size-mb] [threads]
```

**Example - Download and Import Canada:**
```bash
./manage.sh download https://download.geofabrik.de/north-america/canada-latest.osm.pbf --import
# or with custom cache and thread settings
./manage.sh download https://download.geofabrik.de/north-america/canada-latest.osm.pbf --import --cache 4096 --threads 8
```

**Recommended test regions:**
- Canada: ~2.5GB (large country)
- Austria: ~600MB (medium country)
- Japan: ~1.2GB (island nation)
- Germany: ~3.5GB (large country)

Browse all available regions at: https://download.geofabrik.de/

### 3. Access your tile server

Once import is complete, access your tile server at:
```
http://localhost/osm_tiles/{z}/{x}/{y}.png
```

Example tile URL:
```
http://localhost/osm_tiles/0/0/0.png
```

## Manual Setup (Alternative)

If you prefer to do steps manually:

### 1. Start the containers

```bash
./manage.sh start
```

### 2. Download OSM data manually

Create a data directory and download your region:

```bash
mkdir -p osm-data
cd osm-data
wget https://download.geofabrik.de/europe/monaco-latest.osm.pbf
cd ..
```

### 3. Import the data

```bash
./manage.sh import /data/monaco-latest.osm.pbf
```


## Configuration

### Key Technical Details

This setup uses OpenStreetMap Carto with **flex mode** (osm2pgsql flex output), which is the current standard. Key components that are automatically configured:

1. **Mapnik XML with Network PostgreSQL Connection** - The Dockerfile automatically configures the mapnik.xml file with host, port, user, and password parameters for connecting to PostgreSQL over the network (not Unix sockets)

2. **SQL Functions** - Required flex mode functions (`carto_path_type`, etc.) are automatically installed from `functions.sql` on first startup

3. **External Shapefiles** - Water polygons, ice sheets, and other external data are automatically downloaded and imported on first startup

4. **Flex Mode Import** - Uses `osm2pgsql --output flex` with the `openstreetmap-carto-flex.lua` style file

### Environment Variables

Copy `.env.example` to `.env` and adjust values:

```bash
cp .env.example .env
```

Key settings:
- `OSM_IMPORT_CACHE` - Memory cache for import (default: 2048MB)
- `THREADS` - Number of parallel threads (default: 4)
- PostgreSQL tuning parameters (adjust based on your RAM)

### Memory Recommendations

| RAM Available | OSM_IMPORT_CACHE | SHARED_BUFFERS | MAINTENANCE_WORK_MEM |
|---------------|------------------|----------------|----------------------|
| 4GB           | 1024             | 512MB          | 1GB                  |
| 8GB           | 2048             | 1GB            | 4GB                  |
| 16GB          | 4096             | 2GB            | 10GB                 |
| 32GB+         | 8192             | 4GB            | 16GB                 |

## Usage

### View logs

```bash
# All services
./manage.sh logs

# Just tile server (use docker-compose directly for specific service)
docker-compose logs -f tile-server

# Just database (use docker-compose directly for specific service)
docker-compose logs -f postgres
```

### Check status

```bash
./manage.sh status
```

### Restart services

```bash
./manage.sh restart
```

### Stop services

```bash
./manage.sh stop
```

### Stop and remove all data

```bash
./manage.sh clean-all
```

### Check import progress

During import, you can check progress in the logs:

```bash
./manage.sh logs
# Or for just the tile server:
docker-compose logs -f tile-server
```

### Pre-render tiles (optional)

To pre-render tiles for a specific area and zoom levels:

```bash
docker-compose exec tile-server render_list \
  -m default \
  -a \
  -z 0 \
  -Z 10 \
  -x <min_x> \
  -X <max_x> \
  -y <min_y> \
  -Y <max_y>
```

## Testing Your Tile Server

### Using curl

```bash
# Get a single tile
curl http://localhost/osm_tiles/0/0/0.png -o test-tile.png
```

### Using a web browser

Create a simple HTML file to test your tiles with Leaflet:

```html
<!DOCTYPE html>
<html>
<head>
    <title>OSM Tile Server Test</title>
    <link rel="stylesheet" href="https://unpkg.com/leaflet@1.9.4/dist/leaflet.css" />
    <script src="https://unpkg.com/leaflet@1.9.4/dist/leaflet.js"></script>
    <style>
        #map { height: 600px; }
    </style>
</head>
<body>
    <div id="map"></div>
    <script>
        // Set coordinates to center of your region
        var map = L.map('map').setView([49.6116, 6.1319], 13); // Luxembourg

        L.tileLayer('http://localhost/osm_tiles/{z}/{x}/{y}.png', {
            maxZoom: 19,
            attribution: '© OpenStreetMap contributors'
        }).addTo(map);
    </script>
</body>
</html>
```

## Troubleshooting

For detailed troubleshooting information, see [TROUBLESHOOTING.md](TROUBLESHOOTING.md).

### Quick Solutions

### Container won't start

Check logs:
```bash
./manage.sh logs
```

### Import fails with memory errors

Reduce `OSM_IMPORT_CACHE` in your environment or docker-compose.yml:
```bash
docker-compose exec tile-server bash -c "export OSM_IMPORT_CACHE=1024 && /usr/local/bin/import-osm.sh /data/your-file.osm.pbf"
```

### Tiles not rendering

1. Check if data was imported:
```bash
docker-compose exec postgres psql -U renderaccount -d gis -c "SELECT COUNT(*) FROM planet_osm_point;"
```

2. Check renderd status:
```bash
docker-compose exec tile-server ps aux | grep renderd
```

3. Check Apache status:
```bash
docker-compose exec tile-server apache2ctl status
```

4. Test if tiles are being served:
```bash
curl http://localhost/osm_tiles/0/0/0.png -o test-tile.png
file test-tile.png  # Should show: PNG image data
```

### Database connection issues

Ensure PostgreSQL is ready:
```bash
docker-compose exec postgres pg_isready
```

### Error: "function carto_path_type does not exist"

The SQL functions required by flex mode need to be installed. This should happen automatically on container start, but you can install them manually:

```bash
docker-compose exec tile-server bash -c "export PGPASSWORD=renderpassword && psql -h postgres -U renderaccount -d gis -f /home/renderer/src/openstreetmap-carto/functions.sql"
docker-compose restart tile-server
```

### Error: "relation 'icesheet_polygons' does not exist"

External shapefiles need to be downloaded. This should happen automatically on container start, but you can download them manually:

```bash
docker-compose exec tile-server bash -c "cd /home/renderer/src/openstreetmap-carto && export PGHOST=postgres PGPORT=5432 PGDATABASE=gis PGUSER=renderaccount PGPASSWORD=renderpassword && python3 scripts/get-external-data.py"
docker-compose restart tile-server
```

### Error: "connection to server on socket" (Unix socket error)

This indicates a PostgreSQL connection issue. The fix is already implemented in the Dockerfile which configures mapnik.xml with network connection parameters. If you still see this:

1. Rebuild the containers:
```bash
./manage.sh stop
./manage.sh rebuild
```

2. Verify the mapnik.xml has correct connection parameters:
```bash
docker-compose exec tile-server grep -A 5 "Parameter name=\"host\"" /home/renderer/src/openstreetmap-carto/mapnik.xml | head -10
```

You should see host, port, dbname, user, and password parameters.

## Project Structure

```
osm-server/
├── docker-compose.yml          # Main Docker Compose configuration
├── Dockerfile                  # Tile server container definition
├── README.md                   # Main documentation (this file)
├── TROUBLESHOOTING.md         # Detailed troubleshooting guide
├── QUICK_REFERENCE.md         # Quick command reference
├── .env.example               # Environment variables template
├── configs/
│   ├── renderd.conf           # Renderd configuration
│   └── apache-tile.conf       # Apache virtual host configuration
├── scripts/
│   ├── entrypoint.sh          # Container startup script
│   ├── import-osm.sh          # OSM data import script
│   ├── init-db.sh             # Database initialization script
│   └── setup-carto.sh         # Mapnik configuration script (legacy)
├── manage.sh                  # Management command wrapper
└── test-map.html              # Interactive test page
```

## Performance Tips

1. **Use SSDs** - Tile rendering is I/O intensive
2. **Increase RAM** - More RAM = faster imports and rendering
3. **Pre-render tiles** - Render common zoom levels in advance
4. **Tune PostgreSQL** - Adjust settings based on your hardware
5. **Use smaller regions** - Start with a city or small country

## Data Sources

- **Geofabrik**: https://download.geofabrik.de/ (regional extracts, updated daily)
- **Planet OSM**: https://planet.openstreetmap.org/pbf/ (full planet file, ~70GB)
- **BBBike**: https://extract.bbbike.org/ (custom extracts)

## Updating Data

To update your map data:

1. Download the latest extract
2. Stop the tile server
3. Clear the tile cache
4. Re-import the data

```bash
./manage.sh clean-tiles
./manage.sh download <your-region-url>
```

## License

This setup is based on open-source software:
- OpenStreetMap data: ODbL
- Software components: Various open-source licenses

## Credits

Based on the [Switch2OSM tutorial](https://switch2osm.org/serving-tiles/manually-building-a-tile-server-ubuntu-24-04-lts/) by the OpenStreetMap community.
