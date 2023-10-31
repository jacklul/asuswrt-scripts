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

REMOTE="remote:" # remote to use
PARAMETERS="--buffer-size 1M --progress --stats 1s --verbose" # optional parameters
CONFIG_FILE="/jffs/rclone.conf" # Rclone configuration file
FILTER_FILE="/jffs/rclone.list" # Rclone filter/list file
RCLONE_PATH="" # path to Rclone binary
LOG_FILE="/tmp/rclone.log" # log file
NVRAMTXT_FILE="/tmp/nvram.txt" # file to dump 'nvram show' result to, empty means don't dump
NVRAMCFG_FILE="/tmp/nvram.cfg" # file to 'nvram save' to, empty means don't save
CRON="0 6 * * 7"

if [ -f "$SCRIPT_CONFIG" ]; then
    #shellcheck disable=SC1090
    . "$SCRIPT_CONFIG"
fi

case "$1" in
    "run")
        # Detect when installed through Entware
        if [ -z "$RCLONE_PATH" ] && [ -f "/opt/bin/rclone" ]; then
            RCLONE_PATH="/opt/bin/rclone"
        fi

        # Install it through Entware then remove it after we are done
        if [ -z "$RCLONE_PATH" ] && [ -f "/opt/bin/opkg" ]; then
            logger -st "$SCRIPT_TAG" "Installing Rclone..."

            if /opt/bin/opkg update && /opt/bin/opkg install rclone; then
                RCLONE_PATH="/opt/bin/rclone"

                if mount | grep "on /opt " | grep -q "tmpfs"; then
                    ENTWARE_ON_TMPFS=1
                fi
            else
                logger -st "$SCRIPT_TAG" "Failed to install Rclone!"
            fi
        fi

        { [ "$(nvram get wan0_state_t)" != "2" ] && [ "$(nvram get wan1_state_t)" != "2" ]; } && { echo "WAN network is not connected"; exit 1; }
        [ ! -f "$CONFIG_FILE" ] && { logger -st "$SCRIPT_TAG" "Could not find Rclone configuration file: $CONFIG_FILE"; exit 1; }
        [ ! -f "$FILTER_FILE" ] && { logger -st "$SCRIPT_TAG" "Could not find filter file: $FILTER_FILE"; exit 1; }
        [ ! -f "$RCLONE_PATH" ] && { logger -st "$SCRIPT_TAG" "Could not find Rclone binary: $RCLONE_PATH"; exit 1; }

        logger -st "$SCRIPT_TAG" "Creating backup..."

        echo "" > "$LOG_FILE"
        [ -n "$NVRAMTXT_FILE" ] && nvram show > "$NVRAMTXT_FILE" 2>/dev/null
        [ -n "$NVRAMCFG_FILE" ] && nvram save "$NVRAMCFG_FILE" 2>/dev/null

        #shellcheck disable=SC2086
        "$RCLONE_PATH" sync --config "$CONFIG_FILE" --filter-from="$FILTER_FILE" / "$REMOTE" --log-file="$LOG_FILE" $PARAMETERS
        STATUS="$?"

        rm -f "$NVRAMTXT_FILE" "$NVRAMCFG_FILE"
        
        if [ -n "$ENTWARE_ON_TMPFS" ]; then
            logger -st "$SCRIPT_TAG" "Uninstalling Rclone..."
            /opt/bin/opkg remove rclone --autoremove
        fi

        if [ "$STATUS" = "0" ]; then
            logger -st "$SCRIPT_TAG" "Backup completed successfully"
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
