#!/bin/sh
# $2 = subsystem, $3 = action
# set path to this script to EXECUTE_COMMAND variable in hotplug-event.conf
# to fix AsusWRT USB network (github.com/jacklul/asuswrt-usb-raspberry-pi)
# not starting when also using Entware because /opt is already mounted

[ -z "$2" ] && exit

case "$2" in
    "add")
        case "$1" in
            "block")
                #shellcheck disable=SC2125
                ASUSWRT_USB_NETWORK_GLOB=/tmp/mnt/*/asusware*/etc/init.d/S50asuswrt-usb-network
                #shellcheck disable=SC2086
                [ -f $ASUSWRT_USB_NETWORK_GLOB ] && sh $ASUSWRT_USB_NETWORK_GLOB start
            ;;
        esac
    ;;
    "remove")
        case "$1" in
            "block"|"net")
                # This prevents /rom/.asusrouter->/usr/sbin/app_init_run.sh from copying /opt/etc/init.d/S* to /opt/*.1
                nvram set apps_mounted_path=/tmp/mnt/invalid
            ;;
        esac
    ;;
esac
