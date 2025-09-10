#!/bin/sh
# Made by Jack'lul <jacklul.github.io>
#
# Run fstrim on all mounted SSDs on a schedule
#
# Based on:
#  https://github.com/kuchkovsky/asuswrt-merlin-scripts/blob/main/jffs/scripts/trim_ssd.sh
#  https://github.com/kuchkovsky/asuswrt-merlin-scripts/blob/main/jffs/scripts/ssd_provisioning_mode.sh
#

#jas-update=fstrim.sh
#shellcheck disable=SC2155
#shellcheck source=./common.sh
readonly common_script="$(dirname "$0")/common.sh"
if [ -f "$common_script" ]; then . "$common_script"; else { echo "$common_script not found"; exit 1; } fi

CRON="0 3 * * 7" # schedule as cron string
CHANGE_PROVISIONING_MODE=false # set provisioning mode to 'unset' for applicable block devices, needed for some storage devices

load_script_config

is_valid_ssd_device() {
    [ -z "$1" ] && { echo "Device name not provided"; return 1; }
    [ ! -d "/sys/block/$1" ] && { echo "Device not found: /sys/block/$1"; return 1; }

    _dev="/sys/block/$1"

    # Check if device is SSD
    rotational=$(cat "$dev/queue/rotational" 2> /dev/null || echo "N/A")
    if [ "$rotational" != "0" ]; then
        echo "Device is not an SSD: $_dev"
        return 1
    fi

    # Check if TRIM is supported
    max_discard=$(cat "$dev/queue/discard_max_hw_bytes" 2> /dev/null || echo "N/A")
    if [ "$max_discard" = "N/A" ] || [ "$max_discard" -eq 0 ]; then
        echo "Device does not support discard: $_dev"
        return 1
    fi

    return 0
}

change_provisioning_mode() {
    [ -z "$1" ] && { echo "Device name not provided"; return 1; }
    [ ! -d "/sys/block/$1" ] && { echo "Device not found: /sys/block/$1"; return 1; }

    # Set provisioning_mode to 'unmap' to allow TRIM commands to go through
    find "/sys/block/$1/device" -type f -name "provisioning_mode" | while read -r file; do
        [ -z "$file" ] && continue

        _contents=$(cat "$file" 2> /dev/null || echo "")

        if [ "$_contents" != "unmap" ]; then
            echo "Writing 'unmap' to '$file'"
            echo "unmap" > "$file"
        fi
    done
}

case "$1" in
    "run")
        type fstrim > /dev/null 2>&1 || { logecho "Error: Command 'fstrim' not found"; exit 1; }

        lockfile lockfail

        for dev in /sys/block/*; do
            name=$(basename "$dev")

            if
                [ "$(echo "$name" | cut -c 1-2)" = "sd" ] ||
                [ "$(echo "$name" | cut -c 1-4)" = "nvme" ] ||
                [ "$(echo "$name" | cut -c 1-6)" = "mmcblk" ]
            then
                is_valid_ssd_device "$name" || continue
                [ "$CHANGE_PROVISIONING_MODE" = true ] && change_provisioning_mode "$name"

                trimmed=""
                mount | grep "/dev/$name" | while read -r line; do
                    mount_device=$(echo "$line" | awk '{print $1}')
                    mount_point=$(echo "$line" | awk '{print $3}')

                    # Avoid trimming same block device multiple times
                    if echo "$trimmed" | grep -Fq "$mount_device"; then
                        continue
                    fi

                    trimmed="$trimmed $mount_device"
                    output="$(fstrim -v "$mount_point" 2>&1)"
                    status=$?
                    log="/tmp/fstrim_$name.log"
                    #shellcheck disable=SC3037
                    echo -e "$output" > "$log"

                    #shellcheck disable=SC2181
                    if [ "$status" -eq 0 ]; then
                        logecho "Executed fstrim on '$mount_device' ($mount_point)" true
                    else
                        logecho "Failed to execute fstrim on '$mount_device' - check '$log' for details"
                    fi
                done
            fi
        done

        lockfile unlock
    ;;
    "hotplug")
        if [ "$CHANGE_PROVISIONING_MODE" = true ] && [ "$SUBSYSTEM" = "block" ] && [ -n "$DEVICENAME" ]; then
            case "$ACTION" in
                "add")
                    change_provisioning_mode "$DEVICENAME"
                ;;
            esac
        fi
    ;;
    "start")
        type fstrim > /dev/null 2>&1 || echo "Warning: Command 'fstrim' not found"

        if [ "$CHANGE_PROVISIONING_MODE" = true ]; then
            for dev in /sys/block/*; do
                name=$(basename "$dev")

                if
                    [ "$(echo "$name" | cut -c 1-2)" = "sd" ] ||
                    [ "$(echo "$name" | cut -c 1-4)" = "nvme" ] ||
                    [ "$(echo "$name" | cut -c 1-6)" = "mmcblk" ]
                then
                    is_valid_ssd_device "$name" || continue
                    change_provisioning_mode "$name"
                fi
            done
        fi

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
