#!/bin/sh
# Made by Jack'lul <jacklul.github.io>
#
# Backup important stuff using Rclone
#
# Note that automatic download of Rclone binary stores it in /tmp directory - make sure you have enough free RAM!
# This script will detect if Rclone was installed through Entware and set RCLONE_PATH automatically when left empty
#

#jacklul-asuswrt-scripts-update=rclone-backup.sh
#shellcheck disable=SC2155

readonly script_path="$(readlink -f "$0")"
readonly script_name="$(basename "$script_path" .sh)"
readonly script_dir="$(dirname "$script_path")"
readonly script_config="$script_dir/$script_name.conf"

REMOTE="remote:" # remote to use
PARAMETERS="--buffer-size 1M --progress --stats 1s --verbose" # optional parameters
CONFIG_FILE="/jffs/rclone.conf" # Rclone configuration file
FILTER_FILE="/jffs/rclone.list" # Rclone filter/list file
SCRIPT_PRE="/jffs/rclone-pre.sh" # execute a command before running rclone command
SCRIPT_POST="/jffs/rclone-post.sh" # execute a command after running rclone command
RCLONE_PATH="" # path to Rclone binary
LOG_FILE="/tmp/rclone.log" # log file
NVRAMTXT_FILE="/tmp/nvram.txt" # file to dump 'nvram show' result to, empty means don't dump
NVRAMCFG_FILE="/tmp/nvram.cfg" # file to 'nvram save' to, empty means don't save
CRON="0 6 * * 7" # schedule as cron string

if [ -f "$script_config" ]; then
    #shellcheck disable=SC1090
    . "$script_config"
fi

case "$1" in
    "run")
        # Detect when installed through Entware
        if [ -z "$RCLONE_PATH" ] && [ -f /opt/bin/rclone ]; then
            RCLONE_PATH="/opt/bin/rclone"
        fi

        # Install it through Entware then remove it after we are done
        if [ -z "$RCLONE_PATH" ] && [ -f /opt/bin/opkg ]; then
            logger -st "$script_name" "Installing Rclone..."

            # Required to setup execution env for OPKG
            PATH=/opt/bin:/opt/sbin:$PATH

            if opkg update && opkg install rclone; then
                RCLONE_PATH="/opt/bin/rclone"

                if mount | grep "on /opt " | grep -q "tmpfs"; then
                    entware_on_tmpfs=1
                fi
            else
                logger -st "$script_name" "Failed to install Rclone!"
            fi
        fi

        { [ "$(nvram get wan0_state_t)" != "2" ] && [ "$(nvram get wan1_state_t)" != "2" ] ; } && { echo "WAN network is not connected"; exit 1; }
        [ ! -f "$CONFIG_FILE" ] && { logger -st "$script_name" "Could not find Rclone configuration file: $CONFIG_FILE"; exit 1; }
        [ ! -f "$FILTER_FILE" ] && { logger -st "$script_name" "Could not find filter file: $FILTER_FILE"; exit 1; }
        [ ! -f "$RCLONE_PATH" ] && { logger -st "$script_name" "Could not find Rclone binary: $RCLONE_PATH"; exit 1; }

        if [ -n "$SCRIPT_PRE" ] && [ -x "$SCRIPT_PRE" ]; then
            logger -st "$script_name" "Executing script '$SCRIPT_PRE'..."

            #shellcheck disable=SC1090
            . "$SCRIPT_PRE"
        fi

        logger -st "$script_name" "Creating backup..."

        [ -n "$NVRAMTXT_FILE" ] && nvram show > "$NVRAMTXT_FILE" 2> /dev/null
        [ -n "$NVRAMCFG_FILE" ] && nvram save "$NVRAMCFG_FILE" 2> /dev/null

        if [ -n "$LOG_FILE" ]; then
            echo "" > "$LOG_FILE"
            PARAMETERS="--log-file=$LOG_FILE $PARAMETERS"
        fi

        #shellcheck disable=SC2086
        "$RCLONE_PATH" sync --config "$CONFIG_FILE" --filter-from="$FILTER_FILE" / "$REMOTE" $PARAMETERS
        status="$?"

        rm -f "$NVRAMTXT_FILE" "$NVRAMCFG_FILE"

        if [ -n "$SCRIPT_POST" ] && [ -x "$SCRIPT_POST" ]; then
            logger -st "$script_name" "Executing script '$SCRIPT_POST'..."

            #shellcheck disable=SC1090
            . "$SCRIPT_POST"
        fi

        if [ -n "$entware_on_tmpfs" ]; then
            logger -st "$script_name" "Uninstalling Rclone..."

            if ! /opt/bin/opkg remove rclone --autoremove; then
                logger -st "$script_name" "Failed to uninstall Rclone!"
            fi
        fi

        if [ "$status" -eq 0 ]; then
            logger -st "$script_name" "Backup completed successfully"
        else
            if [ -n "$LOG_FILE" ]; then
                logger -st "$script_name" "There was an error while running backup, check '$LOG_FILE' for details"
            else
                logger -st "$script_name" "There was an error while running backup"
            fi

            exit 1
        fi
    ;;
    "start")
        [ ! -f "$CONFIG_FILE" ] && { logger -st "$script_name" "Unable to start - Rclone configuration file ($CONFIG_FILE) not found"; exit 1; }

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
