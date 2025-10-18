FROM ubuntu:24.04

ENV DEBIAN_FRONTEND=noninteractive
ENV AUTOVACUUM=on
ENV UPDATES=disabled

# Install dependencies
RUN apt-get update && apt-get install -y \
    screen \
    locate \
    libapache2-mod-tile \
    renderd \
    git \
    tar \
    unzip \
    wget \
    bzip2 \
    apache2 \
    lua5.1 \
    mapnik-utils \
    python3-mapnik \
    python3-psycopg2 \
    python3-yaml \
    gdal-bin \
    npm \
    node-carto \
    postgresql-client \
    osm2pgsql \
    net-tools \
    curl \
    fonts-noto-cjk \
    fonts-noto-hinted \
    fonts-noto-unhinted \
    fonts-hanazono \
    fonts-unifont \
    sudo \
    && rm -rf /var/lib/apt/lists/*

# Create renderer user
RUN useradd -m -d /home/renderer -s /bin/bash renderer && \
    echo "renderer ALL=(ALL) NOPASSWD:ALL" >> /etc/sudoers

# Set up directories
RUN mkdir -p /home/renderer/src && \
    chown -R renderer:renderer /home/renderer

# Switch to renderer user
USER renderer
WORKDIR /home/renderer

# Install mapnik stylesheet
RUN cd /home/renderer/src && \
    git clone https://github.com/gravitystorm/openstreetmap-carto.git && \
    cd openstreetmap-carto && \
    # Generate mapnik.xml from project.mml
    carto project.mml > mapnik.xml && \
    # CRITICAL FIX: Replace Unix socket DB connection with network connection parameters
    # The generated mapnik.xml defaults to Unix socket connections, but in Docker
    # PostgreSQL runs in a separate container requiring network connections.
    # This sed command replaces the simple dbname parameter with full connection details.
    sed -i 's/<Parameter name="dbname"><!\[CDATA\[gis\]\]><\/Parameter>/<Parameter name="host"><![CDATA[postgres]]><\/Parameter>\n        <Parameter name="port"><![CDATA[5432]]><\/Parameter>\n        <Parameter name="dbname"><![CDATA[gis]]><\/Parameter>\n        <Parameter name="user"><![CDATA[renderaccount]]><\/Parameter>\n        <Parameter name="password"><![CDATA[renderpassword]]><\/Parameter>/g' mapnik.xml

# Create data directory for shapefiles (will be downloaded at runtime)
RUN cd /home/renderer/src/openstreetmap-carto && \
    mkdir -p data

# Switch back to root for final setup
USER root

# Configure renderd
COPY --chown=renderer:renderer configs/renderd.conf /etc/renderd.conf

# Configure Apache
COPY configs/apache-tile.conf /etc/apache2/sites-available/000-default.conf
RUN a2enmod tile && \
    a2enmod headers && \
    a2enmod rewrite

# Create tile directory
RUN mkdir -p /var/lib/mod_tile && \
    chown renderer:renderer /var/lib/mod_tile

# Copy scripts
COPY scripts/entrypoint.sh /usr/local/bin/entrypoint.sh
COPY scripts/import-osm.sh /usr/local/bin/import-osm.sh
RUN chmod +x /usr/local/bin/entrypoint.sh /usr/local/bin/import-osm.sh

EXPOSE 80

ENTRYPOINT ["/usr/local/bin/entrypoint.sh"]
