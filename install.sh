#!/bin/sh
# Simple installer for https://github.com/jacklul/asuswrt-scripts

[ ! -d /jffs ] && exit 1

set -e
umask 022

[ ! -d /jffs/scripts ] && mkdir -m 755 /jffs/scripts
[ -f /jffs/scripts/jas.sh ] && { echo "Script /jffs/scripts/jas.sh already exists!"; exit 1; }

if type curl >/dev/null 2>&1; then
    curl "https://raw.githubusercontent.com/jacklul/asuswrt-scripts/master/jas.sh" -o /jffs/scripts/jas.sh
elif type wget >/dev/null 2>&1; then
    wget "https://raw.githubusercontent.com/jacklul/asuswrt-scripts/master/jas.sh" -O /jffs/scripts/jas.sh
else
    exit 1
fi

/bin/sh /jffs/scripts/jas.sh setup
