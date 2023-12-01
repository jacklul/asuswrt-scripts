#!/bin/sh
# $2 = subsystem, $3 = action
# add this script to EXECUTE_COMMAND in hotplug-event.conf
# to fix Entware in RAM combined with USB network
#  (github.com/jacklul/asuswrt-usb-raspberry-pi)

[ -z "$2" ] && exit

case "$1" in
    "net")
        FOUND=false

        for INTERFACE in /sys/class/net/usb*; do
            [ -d "$INTERFACE" ] && FOUND=true && break
        done

        if [ "$FOUND" = true ]; then
            /jffs/scripts/entware.sh start
        else
            /jffs/scripts/entware.sh stop
        fi
    ;;
esac
