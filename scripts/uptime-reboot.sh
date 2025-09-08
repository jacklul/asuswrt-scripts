#!/bin/sh
# Made by Jack'lul <jacklul.github.io>
#
# Reboot the router after reaching certain uptime
#

#jas-update=uptime-reboot.sh
#shellcheck disable=SC2155
#shellcheck source=./common.sh
readonly common_script="$(dirname "$0")/common.sh"
if [ -f "$common_script" ]; then . "$common_script"; else { echo "$common_script not found"; exit 1; } fi

TARGET_UPTIME=604800 # target uptime value in seconds, 604800 is 7 days
CRON="0 5 * * *" # schedule as cron string

load_script_config

case "$1" in
    "run")
        if [ -n "$TARGET_UPTIME" ] && [ "$TARGET_UPTIME" != "0" ]; then
            current_uptime=$(awk -F '.' '{print $1}' /proc/uptime)

            if [ "$current_uptime" -ge "$TARGET_UPTIME" ]; then
                logger -st "$script_name" "System uptime (${current_uptime}s) is bigger than target (${TARGET_UPTIME}s) - rebooting system now!"
                crontab_entry delete
                service reboot
            fi
        fi
    ;;
    "start")
        [ -z "$TARGET_UPTIME" ] && { logger -st "$script_name" "Error: Target uptime is not set"; exit 1; }
        [ -n "$CRON" ] && crontab_entry add "$CRON $script_path run"
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
