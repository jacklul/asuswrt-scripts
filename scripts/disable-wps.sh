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

readonly SCRIPT_PATH="$(readlink -f "$0")"
readonly SCRIPT_NAME="$(basename "$SCRIPT_PATH" .sh)"
readonly SCRIPT_DIR="$(dirname "$SCRIPT_PATH")"
readonly SCRIPT_CONFIG="$SCRIPT_DIR/$SCRIPT_NAME.conf"
readonly SCRIPT_TAG="$(basename "$SCRIPT_PATH")"

CRON="0 0 * * *"

if [ -f "$SCRIPT_CONFIG" ]; then
    #shellcheck disable=SC1090
    . "$SCRIPT_CONFIG"
fi

case "$1" in
    "run")
        if [ "$(nvram get wl0_wps_mode)" != "disabled" ] || [ "$(nvram get wps_enable)" != "0" ] || [ "$(nvram get wps_enable_x)" != "0" ]; then
            nvram set wl0_wps_mode=disabled
            nvram set wps_enable=0
            nvram set wps_enable_x=0
            nvram commit

            logger -st "$SCRIPT_TAG" "WPS has been disabled"
            service restart_wireless
        fi
    ;;
    "start")
        cru a "$SCRIPT_NAME" "$CRON $SCRIPT_PATH run"

        if [ "$(awk -F '.' '{print $1}' /proc/uptime)" -lt "300" ]; then
            { sleep 60 && sh "$SCRIPT_PATH" run; } & # delay when freshly booted
        else
            sh "$SCRIPT_PATH" run
        fi
    ;;
    "stop")
        [ -x "$SCRIPT_DIR/cron-queue.sh" ] && sh "$SCRIPT_DIR/cron-queue.sh" remove "$SCRIPT_NAME"
        cru d "$SCRIPT_NAME"
    ;;
    "restart")
        sh "$SCRIPT_PATH" stop
        sh "$SCRIPT_PATH" start
    ;;
    *)
        echo "Usage: $0 run|start|stop|restart"
        exit 1
    ;;
esac
