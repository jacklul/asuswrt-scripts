#!/bin/sh
# Made by Jack'lul <jacklul.github.io>
#
# Backup important stuff using Rclone
#
# Keep in mind that that Rclone binary is over 40MB and
# should not be stored on the /jffs partition!
#

#shellcheck disable=SC2155

PARAMETERS="--buffer-size 1M" # optional parameters
REMOTE="remote:" # remote to use
CONFIG_FILE="/jffs/rclone.conf" # Rclone configuration file
FILTER_FILE="$(dirname "$0")/rclone-backup.list" # Rclone filter file
RCLONE_PATH="" # Path to Rclone binary
LOG_FILE="/tmp/rclone.log" # Log file
NVRAM_FILE="/tmp/nvram.txt" # File to dump NVRAM to
CRON_MINUTE=0
CRON_HOUR=6
CRON_MONTHDAY="*"
CRON_WEEKDAY=7

# This means that this is a Merlin firmware
if [ -f "/usr/sbin/helper.sh" ]; then
    #shellcheck disable=SC1091
    . /usr/sbin/helper.sh

    PARAMETERS_=$(am_settings_get jl_rbackup_parameters)
    REMOTE_=$(am_settings_get jl_rbackup_remote)
    CONFIG_FILE_=$(am_settings_get jl_rbackup_config_file)
    FILTER_FILE_=$(am_settings_get jl_rbackup_filter_file)
    RCLONE_PATH_=$(am_settings_get jl_rbackup_rclone_path)
    LOG_FILE_=$(am_settings_get jl_rbackup_log_file)
    NVRAM_FILE_=$(am_settings_get jl_rbackup_nvram_file)
    CRON_HOUR_=$(am_settings_get jl_rbackup_hour)
    CRON_MINUTE_=$(am_settings_get jl_rbackup_minute)
    CRON_MONTHDAY_=$(am_settings_get jl_rbackup_monthday)
    CRON_WEEKDAY_=$(am_settings_get jl_rbackup_weekday)

    [ -n "$PARAMETERS_" ] && PARAMETERS=$PARAMETERS_
    [ -n "$REMOTE_" ] && REMOTE=$REMOTE_
    [ -n "$CONFIG_FILE_" ] && CONFIG_FILE=$CONFIG_FILE_
    [ -n "$FILTER_FILE_" ] && FILTER_FILE=$FILTER_FILE_
    [ -n "$RCLONE_PATH_" ] && RCLONE_PATH=$RCLONE_PATH_
    [ -n "$LOG_FILE_" ] && LOG_FILE=$LOG_FILE_
    [ -n "$NVRAM_FILE_" ] && NVRAM_FILE=$NVRAM_FILE_
    [ -n "$CRON_HOUR_" ] && CRON_HOUR=$CRON_HOUR_
    [ -n "$CRON_MINUTE_" ] && CRON_MINUTE=$CRON_MINUTE_
    [ -n "$CRON_MONTHDAY_" ] && CRON_MONTHDAY=$CRON_MONTHDAY_
    [ -n "$CRON_WEEKDAY_" ] && CRON_WEEKDAY=$CRON_WEEKDAY_
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
        { [ "$(nvram get wan0_state_t)" != "2" ] && [ "$(nvram get wan1_state_t)" != "2" ]; } && { echo "WAN network is not connected"; exit 1; }
        [ ! -f "$RCLONE_PATH" ] && { logger -s -t "$SCRIPT_NAME" "Could not find Rclone binary: $RCLONE_PATH"; exit 1; }
        [ ! -f "$CONFIG_FILE" ] && { logger -s -t "$SCRIPT_NAME" "Could not find Rclone configuration file: $CONFIG_FILE"; exit 1; }
        [ ! -f "$FILTER_FILE" ] && { logger -s -t "$SCRIPT_NAME" "Could not find filter file: $FILTER_FILE"; exit 1; }

        echo "" > "$LOG_FILE"
        nvram show > "$NVRAM_FILE"

        #shellcheck disable=SC2086
        "$RCLONE_PATH" sync --config "$CONFIG_FILE" --filter-from="$FILTER_FILE" / "$REMOTE" --log-file="$LOG_FILE" $PARAMETERS
        STATUS="$?"

        rm -f "$NVRAM_FILE"

        if [ "$STATUS" = "0" ]; then
            logger -s -t "$SCRIPT_NAME" "Backup completed successfully"
            rm -f "$LOG_FILE"
        else
            logger -s -t "$SCRIPT_NAME" "There was an error while running backup, check $LOG_FILE for details"
            exit 1
        fi
    ;;
    "start")
        [ ! -f "$CONFIG_FILE" ] && { logger -s -t "$SCRIPT_NAME" "Unable to start - Rclone configuration file ($CONFIG_FILE) not found"; exit 1; }

        cru a "$SCRIPT_NAME" "$CRON_MINUTE $CRON_HOUR $CRON_MONTHDAY * $CRON_WEEKDAY $SCRIPT_PATH run"
    ;;
    "stop")
        cru d "$SCRIPT_NAME"
    ;;
    *)
        echo "Usage: $0 run|start|stop"
        exit 1
    ;;
esac
