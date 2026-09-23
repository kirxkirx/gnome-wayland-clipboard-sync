#!/bin/bash
# Build the extensions.gnome.org upload ZIPs, one per extension version.
#
# Usage: tools/pack.sh [LABEL]
#
# Writes dist/gnome-wayland-clipboard-sync[-LABEL]-gnome-40.zip (GNOME 40-44)
# and dist/gnome-wayland-clipboard-sync[-LABEL]-gnome-45.zip (GNOME 45+).
# The ZIPs contain only the files the extension needs; compiled schemas
# are left out, since GNOME 44 and later compile them on install.

set -eu

REPO_DIR=$(cd "$(dirname "$0")/.." && pwd)
DIST="$REPO_DIR/dist"
NAME=gnome-wayland-clipboard-sync${1:+-$1}

mkdir -p "$DIST"
for ext in gnome-40 gnome-45; do
    zip_file="$DIST/$NAME-$ext.zip"
    rm -f "$zip_file"
    (cd "$REPO_DIR/$ext" &&
        zip -q -X -r "$zip_file" . -x 'schemas/gschemas.compiled')
    echo "$zip_file"
    unzip -l "$zip_file" | sed 's/^/    /'
done
