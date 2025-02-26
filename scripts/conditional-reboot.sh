#!/bin/sh
# Made by Jack'lul <jacklul.github.io>
#
# Reboot the router after reaching certain uptime
#

#jacklul-asuswrt-scripts-update=conditional-reboot.sh
#shellcheck disable=SC2155

readonly SCRIPT_PATH="$(readlink -f "$0")"
readonly SCRIPT_NAME="$(basename "$SCRIPT_PATH" .sh)"
readonly SCRIPT_DIR="$(dirname "$SCRIPT_PATH")"
readonly SCRIPT_CONFIG="$SCRIPT_DIR/$SCRIPT_NAME.conf"
readonly SCRIPT_TAG="$(basename "$SCRIPT_PATH")"

TARGET_UPTIME=604800 # target uptime value in seconds, 604800 is 7 days
CRON="0 5 * * *" # schedule as cron string

if [ -f "$SCRIPT_CONFIG" ]; then
    #shellcheck disable=SC1090
    . "$SCRIPT_CONFIG"
fi

case "$1" in
    "run")
        [ -z "$TARGET_UPTIME" ] && { logger -st "$SCRIPT_TAG" "Target uptime is not set"; exit 1; }

        if [ -n "$TARGET_UPTIME" ] && [ "$TARGET_UPTIME" != "0" ]; then
            CURRENT_UPTIME=$(awk -F '.' '{print $1}' /proc/uptime)

            if [ "$CURRENT_UPTIME" -ge "$TARGET_UPTIME" ]; then
                logger -st "$SCRIPT_TAG" "System uptime (${CURRENT_UPTIME}s) is bigger than target (${TARGET_UPTIME}s) - rebooting system now!"
                service reboot
                cru d "$SCRIPT_NAME"
            fi
        fi
    ;;
    "start")
        cru a "$SCRIPT_NAME" "$CRON $SCRIPT_PATH run"
    ;;
    "stop")
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
