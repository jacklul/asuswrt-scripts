#!/bin/sh
# Made by Jack'lul <jacklul.github.io>
#
# Reboot the router after reaching certain uptime
#

#jacklul-asuswrt-scripts-update=conditional-reboot.sh
#shellcheck disable=SC2155

readonly script_path="$(readlink -f "$0")"
readonly script_name="$(basename "$script_path" .sh)"
readonly script_dir="$(dirname "$script_path")"
readonly script_config="$script_dir/$script_name.conf"

TARGET_UPTIME=604800 # target uptime value in seconds, 604800 is 7 days
CRON="0 5 * * *" # schedule as cron string

if [ -f "$script_config" ]; then
    #shellcheck disable=SC1090
    . "$script_config"
fi

case "$1" in
    "run")
        [ -z "$TARGET_UPTIME" ] && { logger -st "$script_name" "Error: Target uptime is not set"; exit 1; }

        if [ -n "$TARGET_UPTIME" ] && [ "$TARGET_UPTIME" != "0" ]; then
            current_uptime=$(awk -F '.' '{print $1}' /proc/uptime)

            if [ "$current_uptime" -ge "$TARGET_UPTIME" ]; then
                logger -st "$script_name" "System uptime (${current_uptime}s) is bigger than target (${TARGET_UPTIME}s) - rebooting system now!"
                service reboot
                cru d "$script_name"
            fi
        fi
    ;;
    "start")
        cru a "$script_name" "$CRON $script_path run"
    ;;
    "stop")
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
