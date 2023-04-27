#!/bin/sh
# Made by Jack'lul <jacklul.github.io>
#
# Backup important stuff using Rclone
#
# Keep in mind that that Rclone binary is over 40MB and should not be stored on the /jffs partition!
#

#shellcheck disable=SC2155

PARAMETERS="--buffer-size 1M --progress --stats 1s --verbose" # optional parameters
REMOTE="remote:" # remote to use
CONFIG_FILE="/jffs/rclone.conf" # Rclone configuration file
FILTER_FILE="$(readlink -f "$(dirname "$0")")/rclone-backup.list" # Rclone filter file
RCLONE_PATH="" # path to Rclone binary, fill RCLONE_DOWNLOAD_URL to automatically download
RCLONE_DOWNLOAD_URL="" # Rclone zip download URL, "https://downloads.rclone.org/rclone-current-linux-arm-v7.zip" should work
REMOVE_BINARY_AFTER=true # remove the binary after script is done, only works when RCLONE_DOWNLOAD_URL is set
LOG_FILE="/tmp/rclone.log" # log file
NVRAM_FILE="/tmp/nvram.txt" # file to dump NVRAM to
CRON="0 6 * * 7"

# This means that this is a Merlin firmware
if [ -f "/usr/sbin/helper.sh" ]; then
    #shellcheck disable=SC1091
    . /usr/sbin/helper.sh

    PARAMETERS_=$(am_settings_get jl_rbackup_parameters)
    REMOTE_=$(am_settings_get jl_rbackup_remote)
    RCLONE_PATH_=$(am_settings_get jl_rbackup_rclone_path)
    CRON_HOUR_=$(am_settings_get jl_rbackup_hour)
    CRON_MINUTE_=$(am_settings_get jl_rbackup_minute)
    CRON_MONTHDAY_=$(am_settings_get jl_rbackup_monthday)
    CRON_MONTH_=$(am_settings_get jl_rbackup_month)
    CRON_WEEKDAY_=$(am_settings_get jl_rbackup_weekday)

    [ -n "$PARAMETERS_" ] && PARAMETERS=$PARAMETERS_
    [ -n "$REMOTE_" ] && REMOTE=$REMOTE_
    [ -n "$RCLONE_PATH_" ] && RCLONE_PATH=$RCLONE_PATH_
    [ -n "$CRON_HOUR_" ] && CRON_HOUR=$CRON_HOUR_ || CRON_HOUR=6
    [ -n "$CRON_MINUTE_" ] && CRON_MINUTE=$CRON_MINUTE_ || CRON_MINUTE_=0
    [ -n "$CRON_MONTHDAY_" ] && CRON_MONTHDAY=$CRON_MONTHDAY_ || CRON_MONTHDAY="*"
    [ -n "$CRON_MONTH_" ] && CRON_MONTH=$CRON_MONTH_ || CRON_MONTH="*"
    [ -n "$CRON_WEEKDAY_" ] && CRON_WEEKDAY=$CRON_WEEKDAY_ || CRON_WEEKDAY=7
    
    CRON="$CRON_MINUTE $CRON_HOUR $CRON_MONTHDAY $CRON_MONTH $CRON_WEEKDAY"
fi

readonly SCRIPT_NAME="$(basename "$0" .sh)"
readonly SCRIPT_PATH="$(readlink -f "$0")"
readonly SCRIPT_CONFIG="$(dirname "$0")/$SCRIPT_NAME.conf"
if [ -f "$SCRIPT_CONFIG" ]; then
    #shellcheck disable=SC1090
    . "$SCRIPT_CONFIG"
fi

download_rclone() {
    if [ -n "$RCLONE_DOWNLOAD_URL" ]; then
        logger -s -t "$SCRIPT_NAME" "Downloading Rclone binary from '$RCLONE_DOWNLOAD_URL'..."
        
        set -e
        mkdir -p /tmp/download
        cd /tmp/download
        curl -fsSL "$RCLONE_DOWNLOAD_URL" -o "rclone.zip"
        unzip -q "rclone.zip"
        mv /tmp/download/*/rclone /tmp/rclone
        rm -fr /tmp/download/*
        chmod +x /tmp/rclone
        set +e

        RCLONE_PATH="/tmp/rclone"
    fi
}

{ [ "$REMOVE_BINARY_AFTER" = "true" ] || [ "$REMOVE_BINARY_AFTER" = true ]; } && REMOVE_BINARY_AFTER="1" || REMOVE_BINARY_AFTER="0"

case "$1" in
    "run")
        { [ "$(nvram get wan0_state_t)" != "2" ] && [ "$(nvram get wan1_state_t)" != "2" ]; } && { echo "WAN network is not connected"; exit 1; }
        [ ! -f "$CONFIG_FILE" ] && { logger -s -t "$SCRIPT_NAME" "Could not find Rclone configuration file: $CONFIG_FILE"; exit 1; }
        [ ! -f "$FILTER_FILE" ] && { logger -s -t "$SCRIPT_NAME" "Could not find filter file: $FILTER_FILE"; exit 1; }

        if [ ! -f "$RCLONE_PATH" ]; then
            download_rclone
            
            [ ! -f "$RCLONE_PATH" ] && { logger -s -t "$SCRIPT_NAME" "Could not find Rclone binary: $RCLONE_PATH"; exit 1; }
        fi

        echo "" > "$LOG_FILE"
        nvram show > "$NVRAM_FILE" 2>/dev/null

        #shellcheck disable=SC2086
        "$RCLONE_PATH" sync --config "$CONFIG_FILE" --filter-from="$FILTER_FILE" / "$REMOTE" --log-file="$LOG_FILE" $PARAMETERS
        STATUS="$?"

        [ "$REMOVE_BINARY_AFTER" = "1" ] && [ -n "$RCLONE_DOWNLOAD_URL" ] && rm -f "$RCLONE_PATH"
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
