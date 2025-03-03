#!/bin/sh
# Made by Jack'lul <jacklul.github.io>
#
# Ensure that WPS is disabled on the router
#
# Based on:
#  https://www.snbforums.com/threads/asus-rt-ac87u-stepped-into-the-382-branch-d.44227/#post-376642
#

#jacklul-asuswrt-scripts-update=disable-wps.sh
#shellcheck disable=SC2155

readonly script_path="$(readlink -f "$0")"
readonly script_name="$(basename "$script_path" .sh)"
readonly script_dir="$(dirname "$script_path")"
readonly script_config="$script_dir/$script_name.conf"

CRON="0 0 * * *" # schedule as cron string

if [ -f "$script_config" ]; then
    #shellcheck disable=SC1090
    . "$script_config"
fi

case "$1" in
    "run")
        if [ "$(nvram get wl0_wps_mode)" != "disabled" ] || [ "$(nvram get wps_enable)" != "0" ] || [ "$(nvram get wps_enable_x)" != "0" ]; then
            nvram set wl0_wps_mode=disabled
            nvram set wps_enable=0
            nvram set wps_enable_x=0
            nvram commit
            service restart_wireless

            logger -st "$script_name" "WPS has been disabled"
        fi
    ;;
    "start")
        cru a "$script_name" "$CRON $script_path run"

        if [ "$(awk -F '.' '{print $1}' /proc/uptime)" -lt 300 ]; then
            { sleep 60 && sh "$script_path" run; } & # delay when freshly booted
        else
            sh "$script_path" run
        fi
    ;;
    "stop")
        [ -x "$script_dir/cron-queue.sh" ] && sh "$script_dir/cron-queue.sh" remove "$script_name"
        cru d "$script_name"
    ;;
    "restart")
        sh "$script_path" stop
        sh "$script_path" start
    ;;
    *)
        echo "Usage: $0 run|start|stop|restart"
        exit 1
    ;;
esac
