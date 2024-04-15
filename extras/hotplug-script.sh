#!/bin/sh
# $2 = subsystem, $3 = action
# add this script to EXECUTE_COMMAND in hotplug-event.conf
# to fix AsusWRT USB network (github.com/jacklul/asuswrt-usb-raspberry-pi)
# not starting when using Entware in RAM
# because /opt is mounted and asusware script can't run

[ -z "$2" ] && exit

if [ "$1" = "block" ] && [ "$2" = "add" ]; then
    #shellcheck disable=SC2125
    ASUSWRT_USB_NETWORK_GLOB=/tmp/mnt/*/asusware*/etc/init.d/S50asuswrt-usb-network
    #shellcheck disable=SC2086
    [ -f $ASUSWRT_USB_NETWORK_GLOB ] && sh $ASUSWRT_USB_NETWORK_GLOB start
fi
