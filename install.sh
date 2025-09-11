#!/bin/sh
# Installer for https://github.com/jacklul/asuswrt-scripts

[ ! -d /jffs ] && { echo "Could not find /jffs"; exit 1; }

branch=master
[ -n "$1" ] && branch="$1"
script_url="https://raw.githubusercontent.com/jacklul/asuswrt-scripts/$branch/jas.sh"

set -e
umask 022

[ ! -d /jffs/scripts ] && mkdir -m 755 /jffs/scripts
[ -f /jffs/scripts/jas.sh ] && { echo "Script /jffs/scripts/jas.sh already exists!"; exit 1; }

if type curl > /dev/null 2>&1; then
    curl "$script_url" -o /jffs/scripts/jas.sh
elif type wget > /dev/null 2>&1; then
    wget "$script_url" -O /jffs/scripts/jas.sh
else
    echo "Could not find either the 'curl' or 'wget' command!"
    exit 1
fi

/bin/sh /jffs/scripts/jas.sh setup
