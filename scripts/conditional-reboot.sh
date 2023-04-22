#!/bin/sh
# Made by Jack'lul <jacklul.github.io>
#
# Reboot the router after reaching certain uptime
#

#shellcheck disable=SC2155

TARGET_UPTIME=604800 # target uptime value in seconds, 604800 is 7 days
CRON_MINUTE=0
CRON_HOUR=4

# This means that this is a Merlin firmware
if [ -f "/usr/sbin/helper.sh" ]; then
    #shellcheck disable=SC1091
    . /usr/sbin/helper.sh

    TARGET_UPTIME_=$(am_settings_get jl_creboot_target_uptime)
    CRON_HOUR_=$(am_settings_get jl_creboot_hour)
    CRON_MINUTE_=$(am_settings_get jl_creboot_minute)

    [ -n "$TARGET_UPTIME_" ] && TARGET_UPTIME=$TARGET_UPTIME_
    [ -n "$CRON_HOUR_" ] && CRON_HOUR=$CRON_HOUR_
    [ -n "$CRON_MINUTE_" ] && CRON_MINUTE=$CRON_MINUTE_
fi

readonly SCRIPT_NAME="$(basename "$0" .sh)"
readonly SCRIPT_PATH="$(readlink -f "$0")"
readonly SCRIPT_CONFIG="$(dirname "$0")/$SCRIPT_NAME.conf"
if [ -f "$SCRIPT_CONFIG" ]; then
    #shellcheck disable=SC1090
    . "$SCRIPT_CONFIG"
fi

case "$1" in
    "run")
        [ -z "$TARGET_UPTIME" ] && { logger -s -t "$SCRIPT_NAME" "Target uptime is not set"; exit 1; }

        if [ -n "$TARGET_UPTIME" ] && [ "$TARGET_UPTIME" != "0" ]; then
            CURRENT_UPTIME=$(awk -F '.' '{print $1}' /proc/uptime)

            if [ "$CURRENT_UPTIME" -ge "$TARGET_UPTIME" ]; then
                logger -s -t "$SCRIPT_NAME" "System uptime (${CURRENT_UPTIME}s) is bigger than target (${TARGET_UPTIME}s) - rebooting"
                service reboot
            fi
        fi
    ;;
    "start")
        cru a "$SCRIPT_NAME" "$CRON_MINUTE $CRON_HOUR * * * $SCRIPT_PATH run"
    ;;
    "stop")
        cru d "$SCRIPT_NAME"
    ;;
    *)
        echo "Usage: $0 run|start|stop"
        exit 1
    ;;
esac
