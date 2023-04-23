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
RCLONE_PATH="" # path to Rclone binary
RCLONE_DOWNLOAD_URL="" # Rclone download URL, "https://downloads.rclone.org/rclone-current-linux-arm-v7.zip" should work
RCLONE_DOWNLOAD_ZIP="$(basename "$RCLONE_DOWNLOAD_URL")" # Rclone download ZIP file name
RCLONE_DOWNLOAD_UNZIP_DIR="/tmp/rclone-download" # Rclone download ZIP unpack destination, should be /tmp, make sure your router has enough RAM
LOG_FILE="/tmp/rclone.log" # log file
NVRAM_FILE="/tmp/nvram.txt" # file to dump NVRAM to
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
    RCLONE_PATH_=$(am_settings_get jl_rbackup_rclone_path)
    CRON_HOUR_=$(am_settings_get jl_rbackup_hour)
    CRON_MINUTE_=$(am_settings_get jl_rbackup_minute)
    CRON_MONTHDAY_=$(am_settings_get jl_rbackup_monthday)
    CRON_WEEKDAY_=$(am_settings_get jl_rbackup_weekday)

    [ -n "$PARAMETERS_" ] && PARAMETERS=$PARAMETERS_
    [ -n "$REMOTE_" ] && REMOTE=$REMOTE_
    [ -n "$RCLONE_PATH_" ] && RCLONE_PATH=$RCLONE_PATH_
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
        [ ! -f "$CONFIG_FILE" ] && { logger -s -t "$SCRIPT_NAME" "Could not find Rclone configuration file: $CONFIG_FILE"; exit 1; }
        [ ! -f "$FILTER_FILE" ] && { logger -s -t "$SCRIPT_NAME" "Could not find filter file: $FILTER_FILE"; exit 1; }

        if [ ! -f "$RCLONE_PATH" ]; then
            if [ -f "$RCLONE_DOWNLOAD_URL" ]; then
                set -e

                DOWNLOAD_DESTINATION="$(dirname "$RCLONE_DOWNLOAD_UNZIP_DIR")"
                cd "$DOWNLOAD_DESTINATION"

                echo "Downloading $RCLONE_DOWNLOAD_URL..."
                curl -fsS "$RCLONE_DOWNLOAD_URL" -o "$DOWNLOAD_DESTINATION/$RCLONE_DOWNLOAD_ZIP"

                echo "Unpacking $RCLONE_DOWNLOAD_ZIP..."
                mkdir -p "$RCLONE_DOWNLOAD_UNZIP_DIR"
                busybox unzip "$RCLONE_DOWNLOAD_ZIP" -d "$RCLONE_DOWNLOAD_UNZIP_DIR"

                echo "Moving Rclone binary..."
                mv "$RCLONE_DOWNLOAD_UNZIP_DIR/"*"/rclone" "$DOWNLOAD_DESTINATION" && chmod +x "$DOWNLOAD_DESTINATION/rclone"
                RCLONE_PATH="$DOWNLOAD_DESTINATION/rclone"

                echo "Cleaning up..."
                rm -fr "$RCLONE_DOWNLOAD_ZIP" "$RCLONE_DOWNLOAD_UNZIP_DIR"

                set +e
            fi

            [ ! -f "$RCLONE_PATH" ] && { logger -s -t "$SCRIPT_NAME" "Could not find Rclone binary: $RCLONE_PATH"; exit 1; }
        fi

        echo "" > "$LOG_FILE"
        nvram show > "$NVRAM_FILE"

        #shellcheck disable=SC2086
        "$RCLONE_PATH" sync --config "$CONFIG_FILE" --filter-from="$FILTER_FILE" / "$REMOTE" --log-file="$LOG_FILE" $PARAMETERS
        STATUS="$?"

        [ -n "$RCLONE_ZIP" ] && rm -f "$RCLONE_PATH"
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
    "restart")
        sh "$SCRIPT_PATH" stop
        sh "$SCRIPT_PATH" start
    ;;
    *)
        echo "Usage: $0 run|start|stop|restart"
        exit 1
    ;;
esac
