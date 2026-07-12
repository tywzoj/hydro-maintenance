#!/usr/bin/env bash

# URL of the GeoLite2 City database (gzipped)
URL="https://cdn.jsdelivr.net/npm/geolite2-city/GeoLite2-City.mmdb.gz"
#URL="https://fastly.jsdelivr.net/npm/geolite2-city/GeoLite2-City.mmdb.gz"

# File names
FILE_NAME="GeoLite2-City.mmdb.gz"
FINAL_NAME="GeoLite2-City.mmdb"

###################### CONFIGURATION END ######################

set -euo pipefail

# Get the Yarn global directory
YARN_GLOBAL_DIR=$(yarn global dir)

# Define the target addon directory
ADDON_DIR="$YARN_GLOBAL_DIR/node_modules/@hydrooj/geoip"

# Ensure the target directory exists
mkdir -p "$ADDON_DIR"

# Download the GeoLite2 database
echo "Downloading GeoLite2 City database..."
curl -L "$URL" -o "$ADDON_DIR/$FILE_NAME"

# Extract the gzipped database file
echo "Extracting database..."
gunzip -f "$ADDON_DIR/$FILE_NAME"

echo "Installation completed."
echo "Database location: $ADDON_DIR/$FINAL_NAME"