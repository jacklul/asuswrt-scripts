#!/bin/sh

cdir="$(dirname "$(readlink -f "$0")")"
find "$cdir" -type d -exec chmod 755 {} +
find "$cdir" -type f -exec chmod 644 {} +
chmod +x "$0" "$cdir/etc/init.d/S50usb-mount-script"
