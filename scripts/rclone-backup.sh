#!/bin/sh
# Made by Jack'lul <jacklul.github.io>
#
# Backup important stuff using Rclone
#
# Note that automatic download of Rclone binary stores it in /tmp directory - make sure you have enough free RAM!
# This script will detect if Rclone was installed through Entware and set RCLONE_PATH automatically when left empty
#

#shellcheck disable=SC2155

readonly SCRIPT_PATH="$(readlink -f "$0")"
readonly SCRIPT_NAME="$(basename "$SCRIPT_PATH" .sh)"
readonly SCRIPT_DIR="$(dirname "$SCRIPT_PATH")"
readonly SCRIPT_CONFIG="$SCRIPT_DIR/$SCRIPT_NAME.conf"
readonly SCRIPT_TAG="$(basename "$SCRIPT_PATH")"

PARAMETERS="--buffer-size 1M --progress --stats 1s --verbose" # optional parameters
REMOTE="remote:" # remote to use
CONFIG_FILE="/jffs/rclone.conf" # Rclone configuration file
FILTER_FILE="/jffs/rclone.list" # Rclone filter file
RCLONE_PATH="" # path to Rclone binary, fill RCLONE_DOWNLOAD_URL to automatically download
RCLONE_DOWNLOAD_URL="" # Rclone zip download URL, "https://downloads.rclone.org/rclone-current-linux-arm-v7.zip" should work
REMOVE_BINARY_AFTER=true # remove the binary after script is done, only works when RCLONE_DOWNLOAD_URL is set
LOG_FILE="/tmp/rclone.log" # log file
NVRAM_FILE="/tmp/nvram.txt" # file to dump NVRAM to
CRON="0 6 * * 7"

if [ -f "$SCRIPT_CONFIG" ]; then
    #shellcheck disable=SC1090
    . "$SCRIPT_CONFIG"
fi

# Detect when installed through Entware
if [ -z "$RCLONE_PATH" ] && [ -f "/opt/bin/rclone" ]; then
    RCLONE_PATH="/opt/bin/rclone"
fi

download_rclone() {
    if [ -n "$RCLONE_DOWNLOAD_URL" ]; then
        logger -st "$SCRIPT_TAG" "Downloading Rclone binary from '$RCLONE_DOWNLOAD_URL'..."

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
        [ ! -f "$CONFIG_FILE" ] && { logger -st "$SCRIPT_TAG" "Could not find Rclone configuration file: $CONFIG_FILE"; exit 1; }
        [ ! -f "$FILTER_FILE" ] && { logger -st "$SCRIPT_TAG" "Could not find filter file: $FILTER_FILE"; exit 1; }

        if [ ! -f "$RCLONE_PATH" ]; then
            download_rclone

            [ ! -f "$RCLONE_PATH" ] && { logger -st "$SCRIPT_TAG" "Could not find Rclone binary: $RCLONE_PATH"; exit 1; }
        fi

        echo "" > "$LOG_FILE"
        nvram show > "$NVRAM_FILE" 2>/dev/null

        #shellcheck disable=SC2086
        "$RCLONE_PATH" sync --config "$CONFIG_FILE" --filter-from="$FILTER_FILE" / "$REMOTE" --log-file="$LOG_FILE" $PARAMETERS
        STATUS="$?"

        [ "$REMOVE_BINARY_AFTER" = "1" ] && [ -n "$RCLONE_DOWNLOAD_URL" ] && rm -f "$RCLONE_PATH"
        rm -f "$NVRAM_FILE"

        if [ "$STATUS" = "0" ]; then
            logger -st "$SCRIPT_TAG" "Backup completed successfully"
            rm -f "$LOG_FILE"
        else
            logger -st "$SCRIPT_TAG" "There was an error while running backup, check $LOG_FILE for details"
            exit 1
        fi
    ;;
    "start")
        [ ! -f "$CONFIG_FILE" ] && { logger -st "$SCRIPT_TAG" "Unable to start - Rclone configuration file ($CONFIG_FILE) not found"; exit 1; }

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
