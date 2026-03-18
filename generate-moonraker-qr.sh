#!/bin/bash

# Usage: generate-moonraker-qr.sh <target> [output.png]
#
# <target> can be any of:
#   hostname              e.g. dragonforge
#   hostname:port         e.g. dragonforge:1234
#   scheme://hostname     e.g. https://dragonforge.localdomain
#   scheme://hostname:port  e.g. https://dragonforge.localdomain:8443

MOONRAKER_PREFIX="web+moonraker:"

TARGET_ARG="$1"
OUTPUT_FILE="${2:-moonraker-host.png}"

if [[ -z "$TARGET_ARG" ]]; then
    echo "Usage: $0 <target> [output.png]"
    echo "Example: $0 dragonforge"
    echo "Example: $0 dragonforge:1234"
    echo "Example: $0 https://dragonforge.localdomain"
    echo "Example: $0 https://192.168.1.100:8443 my-printer.png"
    exit 1
fi

if ! command -v qrencode >/dev/null 2>&1; then
    echo "Error: qrencode is not installed or not in PATH."
    echo "Install it with: sudo apt install qrencode"
    exit 1
fi

QR_CONTENT="${MOONRAKER_PREFIX}${TARGET_ARG}"

qrencode -o "$OUTPUT_FILE" "$QR_CONTENT"

echo "QR code generated: $(realpath "$OUTPUT_FILE")"
echo "Content: $QR_CONTENT"
