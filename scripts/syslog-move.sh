#!/bin/sh
# Made by Jack'lul <jacklul.github.io>
#
# Move syslog log location
#

#shellcheck disable=SC2155

LOG_FILE="/tmp/syslog-moved.log"
DEFAULT_LOG_FILE="/jffs/syslog.log"

# This means that this is a Merlin firmware
if [ -f "/usr/sbin/helper.sh" ]; then
    #shellcheck disable=SC1091
    . /usr/sbin/helper.sh

    LOG_FILE_=$(am_settings_get jl_syslog_log_file)

    [ -n "$LOG_FILE_" ] && LOG_FILE=$LOG_FILE_
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
        [ ! -f "$DEFAULT_LOG_FILE" ] && { logger -s -t "$SCRIPT_NAME" "Syslog file not found: $DEFAULT_LOG_FILE"; exit 1; }

        if ! mount | grep -q "$DEFAULT_LOG_FILE"; then
            cp "$DEFAULT_LOG_FILE" "$LOG_FILE"
            touch "${LOG_FILE}-1"
            
            mount --bind "$LOG_FILE" "$DEFAULT_LOG_FILE"
            mount --bind "${LOG_FILE}-1" "${DEFAULT_LOG_FILE}-1"

            logger -s -t "$SCRIPT_NAME" "Syslog file mounted to $LOG_FILE"
        else
            logger -s -t "$SCRIPT_NAME" "Syslog file is already mounted to $LOG_FILE"
        fi
    ;;
    "start")
        if [ "$(awk -F '.' '{print $1}' /proc/uptime)" -lt "300" ]; then
            { sleep 60 && sh "$SCRIPT_PATH" run; } & # delay when freshly booted
        else
            sh "$SCRIPT_PATH" run
        fi
    ;;
    "stop")
        logger -s -t "$SCRIPT_NAME" "Operations made by this script cannot be reverted - disable it then reboot the router!"
    ;;
    *)
        echo "Usage: $0 run|start|stop"
        exit 1
    ;;
esac
