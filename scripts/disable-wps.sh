#!/bin/sh
# Made by Jack'lul <jacklul.github.io>
#
# Ensure that WPS is disabled on the router
#
# Based on:
#  https://www.snbforums.com/threads/asus-rt-ac87u-stepped-into-the-382-branch-d.44227/#post-376642
#

#jas-update=disable-wps.sh
#shellcheck disable=SC2155
#shellcheck source=./common.sh
readonly common_script="$(dirname "$0")/common.sh"
if [ -f "$common_script" ]; then . "$common_script"; else { echo "$common_script not found"; exit 1; } fi

CRON="0 0 * * *" # schedule as cron string

load_script_config

disable_wps() {
    if [ "$(nvram get wl0_wps_mode)" != "disabled" ] || [ "$(nvram get wps_enable)" != "0" ] || [ "$(nvram get wps_enable_x)" != "0" ]; then
        nvram set wl0_wps_mode=disabled
        nvram set wps_enable=0
        nvram set wps_enable_x=0
        nvram commit
        service restart_wireless

        logger -st "$script_name" "WPS has been disabled"
    fi
}

case "$1" in
    "run")
        disable_wps
    ;;
    "start")
        [ -n "$CRON" ] && crontab_entry add "$CRON $script_path run"

        if [ ! -t 0 ] && [ "$(awk -F '.' '{print $1}' /proc/uptime)" -lt 300 ]; then
            { sleep 60 && disable_wps; } & # delay when freshly booted
        else
            disable_wps
        fi
    ;;
    "stop")
        crontab_entry delete
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
