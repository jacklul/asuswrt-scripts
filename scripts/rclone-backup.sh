#!/bin/sh
# Made by Jack'lul <jacklul.github.io>
#
# Backup important stuff using Rclone
#
# If Entware is available it will try to install Rclone on first backup execution
# If Entware was installed to tmpfs it will uninstall Rclone after execution
#
# Based on:
#  https://github.com/jacklul/rclone-backup
#

#jas-update=rclone-backup.sh
#shellcheck disable=SC2155
#shellcheck source=./common.sh
readonly common_script="$(dirname "$0")/common.sh"
if [ -f "$common_script" ]; then . "$common_script"; else { echo "$common_script not found" >&2; exit 1; } fi

REMOTE="remote:" # remote to use
PARAMETERS="--buffer-size 1M --progress --stats 1s --verbose --log-file=/tmp/rclone-backup.log" # optional parameters
CRON="0 6 * * 7" # schedule as cron string
CONFIG_FILE="/jffs/rclone-backup/rclone.conf" # Rclone configuration file
FILTER_FILE="/jffs/rclone-backup/filter.list" # Rclone filter/list file
SCRIPT_PRE="/jffs/rclone-backup/script-pre.sh" # execute a command before running rclone command
SCRIPT_POST="/jffs/rclone-backup/script-post.sh" # execute a command after running rclone command
RCLONE_PATH="" # path to Rclone binary

load_script_config

case "$1" in
    "run")
        # Detect when installed through Entware
        if [ -z "$RCLONE_PATH" ] && [ -f /opt/bin/rclone ]; then
            RCLONE_PATH="/opt/bin/rclone"
        fi

        # Install it through Entware then remove it after we are done
        if [ -z "$RCLONE_PATH" ] && [ -f /opt/bin/opkg ]; then
            logecho "Installing Rclone..."

            # Required to setup execution env for OPKG
            PATH=/opt/bin:/opt/sbin:$PATH

            if opkg update && opkg install rclone; then
                RCLONE_PATH="/opt/bin/rclone"

                if mount | grep -F "on /opt " | grep -Fq "tmpfs"; then
                    entware_on_tmpfs=1
                fi
            else
                logecho "Failed to install Rclone!" error
            fi
        fi

        { [ "$(nvram get wan0_state_t)" != "2" ] && [ "$(nvram get wan1_state_t)" != "2" ] ; } && { logecho "Error: WAN network is not connected" error; return 1; }
        [ ! -f "$RCLONE_PATH" ] && { logecho "Error: Could not find Rclone binary: $RCLONE_PATH" error; exit 1; }
        [ ! -f "$CONFIG_FILE" ] && { logecho "Error: Could not find Rclone configuration file: $CONFIG_FILE" error; exit 1; }
        [ ! -f "$FILTER_FILE" ] && { logecho "Error: Could not find filter file: $FILTER_FILE" error; exit 1; }

        if [ -n "$SCRIPT_PRE" ] && [ -x "$SCRIPT_PRE" ]; then
            logecho "Executing script '$SCRIPT_PRE'..." alert

            . "$SCRIPT_PRE"
        fi

        logecho "Backing up now..." alert

        #shellcheck disable=SC2086
        "$RCLONE_PATH" sync --config "$CONFIG_FILE" --filter-from="$FILTER_FILE" / "$REMOTE" $PARAMETERS
        status="$?"

        if [ -n "$SCRIPT_POST" ] && [ -x "$SCRIPT_POST" ]; then
            logecho "Executing script '$SCRIPT_POST'..." alert

            . "$SCRIPT_POST"
        fi

        if [ -n "$entware_on_tmpfs" ]; then
            logecho "Uninstalling Rclone..."

            if ! /opt/bin/opkg remove rclone --autoremove; then
                logecho "Failed to uninstall Rclone!" error
            fi
        fi

        if [ "$status" -eq 0 ]; then
            logecho "Finished successfully" alert
        else
            logecho "Finished with error code $status" alert
            exit 1
        fi
    ;;
    "start")
        [ ! -f "$CONFIG_FILE" ] && { logecho "Error: Rclone configuration file '$CONFIG_FILE' not found" error; exit 1; }
        type rclone > /dev/null 2>&1 || { echo "Warning: Command 'rclone' not found" >&2; }
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
