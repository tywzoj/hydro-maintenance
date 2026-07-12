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

# Temporary download directory
TMP_DIR="/tmp/hydrooj-geoip"

# Ensure directories exist
mkdir -p "$ADDON_DIR"
mkdir -p "$TMP_DIR"

# Check aria2c
if ! command -v aria2c >/dev/null 2>&1; then
    echo "aria2c is not installed."
    echo "Install it first:"
    echo "  macOS: brew install aria2"
    echo "  Ubuntu/Debian: sudo apt install aria2"
    exit 1
fi

echo "Downloading GeoLite2 database to /tmp with aria2c..."

# Download with resume support
aria2c \
    --dir="$TMP_DIR" \
    --out="$FILE_NAME" \
    --split=64 \
    --max-connection-per-server=16 \
    --min-split-size=1M \
    --continue=true \
    --auto-file-renaming=false \
    --allow-overwrite=true \
    --retry-wait=2 \
    --max-tries=10 \
    --timeout=30 \
    --summary-interval=0 \
    --console-log-level=warn \
    "$URL"

echo "Extracting database..."

# Keep original gz file for future resume
gunzip -c "$TMP_DIR/$FILE_NAME" > "$TMP_DIR/$FINAL_NAME"

echo "Installing database..."

# Atomic replace
mv "$TMP_DIR/$FINAL_NAME" "$ADDON_DIR/$FINAL_NAME"

echo "Installation completed."
echo "Database location: $ADDON_DIR/$FINAL_NAME"