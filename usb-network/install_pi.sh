#!/bin/bash

[ -f "/rom/jffs.json" ] && { echo "This script must run on the Raspberry Pi!"; exit 1; }
[ "$UID" -eq 0 ] || { echo "This script must run as root!"; exit 1; }
command -v debugfs >/dev/null 2>&1 || { echo "This script requires 'debugfs' command - install it with \"apt-get install e2fsprogs\"."; exit 1; }

SPATH=$(dirname "$0")
REQUIRED_FILES=( asuswrt-usb-network.sh asuswrt-usb-network.service )
DOWNLOAD_PATH=asuswrt-usb-network
DOWNLOAD_URL=https://raw.githubusercontent.com/jacklul/asuswrt-scripts/master/raspberry-pi-usb-network

set -e

MISSING_FILES=0
for FILE in "${REQUIRED_FILES[@]}"; do
    [ ! -f "$SPATH/$FILE" ] && MISSING_FILES=$((MISSING_FILES+1))
done

if [ "$MISSING_FILES" -gt 0 ]; then
    if [ "$MISSING_FILES" != "${#MISSING_FILES[@]}" ]; then
        mkdir -v "$SPATH/$DOWNLOAD_PATH"
        SPATH="$SPATH/$DOWNLOAD_PATH"
    fi

    for FILE in "${REQUIRED_FILES[@]}"; do
        [ ! -f "$SPATH/$FILE" ] && wget -nv -O "$SPATH/$FILE" "$DOWNLOAD_URL/$FILE"
    done
fi

for FILE in "${REQUIRED_FILES[@]}"; do
    [ ! -f "$SPATH/$FILE" ] && { echo "Missing required file for installation: $FILE"; exit 1; }
done

cp -v "$SPATH/asuswrt-usb-network.sh" /usr/local/sbin/asuswrt-usb-network && chmod 755 /usr/local/sbin/asuswrt-usb-network
cp -v "$SPATH/asuswrt-usb-network.service" /etc/systemd/system && chmod 644 /etc/systemd/system/asuswrt-usb-network.service

command -v dos2unix >/dev/null 2>&1 && dos2unix /usr/local/sbin/asuswrt-usb-network

echo "Then enable this service run \"sudo systemctl enable asuswrt-usb-network.service\""
