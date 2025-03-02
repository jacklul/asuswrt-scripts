#!/bin/sh
# $2 = subsystem, $3 = action
# set path to this script to EXECUTE_COMMAND variable in hotplug-event.conf
# to fix AsusWRT USB network (github.com/jacklul/asuswrt-usb-raspberry-pi)
# not starting when also using Entware because /opt is already mounted

#shellcheck disable=SC2125,SC2086

[ -z "$2" ] && exit

case "$2" in
    "add")
        case "$1" in
            "block")
                asuswrt_usb_network=/tmp/mnt/*/asusware*/etc/init.d/S50asuswrt-usb-network
                [ -f $asuswrt_usb_network ] && sh $asuswrt_usb_network start
                usb_mount_script=/tmp/mnt/*/asusware*/etc/init.d/S50usb-mount-script
                [ -f $usb_mount_script ] && sh $usb_mount_script start
            ;;
        esac
    ;;
    "remove")
        case "$1" in
            "block")
                # This prevents /rom/.asusrouter->/usr/sbin/app_init_run.sh from copying /opt/etc/init.d/S* to /opt/*.1
                # In most cases it will stop the Asus apps from starting, which is what we want at this point
                nvram set apps_mounted_path=/tmp/mnt/invalid
            ;;
        esac
    ;;
esac
