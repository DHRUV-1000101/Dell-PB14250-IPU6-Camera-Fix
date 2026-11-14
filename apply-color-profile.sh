#!/bin/bash
set -e

SCRIPT_DIR=$(dirname "$(readlink -f "$0")")
SRC_FILE="$SCRIPT_DIR/ov05c10.yaml"
DEST_DIR="/usr/share/libcamera/ipa/simple"

if [ ! -f "$SRC_FILE" ]; then
    echo "Error: $SRC_FILE not found."
    exit 1
fi

if [ ! -d "$DEST_DIR" ]; then
    echo "Error: Destination directory $DEST_DIR does not exist."
    exit 1
fi

sudo install -m 644 "$SRC_FILE" "$DEST_DIR/ov05c10.yaml"
echo "Copied ov05c10.yaml to $DEST_DIR/"

systemctl --user restart pipewire wireplumber
echo "PipeWire and WirePlumber restarted!"
