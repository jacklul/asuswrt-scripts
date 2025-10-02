#!/bin/sh
# Made by Jack'lul <jacklul.github.io>
#
# Enable swap file on startup
#
# Based on:
#  https://github.com/decoderman/amtm/blob/master/amtm_modules/swap.mod
#

#jas-update=swap.sh
#shellcheck shell=ash
#shellcheck disable=SC2155

#shellcheck source=./common.sh
readonly common_script="$(dirname "$0")/common.sh"
if [ -f "$common_script" ]; then . "$common_script"; else { echo "$common_script not found" >&2; exit 1; } fi

SWAP_FILE="" # swap file path, like /tmp/mnt/USBDEVICE/swap.img, leave empty to search for it in /tmp/mnt/*/swap.img
SWAP_SIZE=1048576 # swap file size, changing after swap is created requires it to be manually removed, 1048576 = 1GB
SWAPPINESS= # change the value of vm.swappiness (/proc/sys/vm/swappiness), if left empty it will not be changed

load_script_config

find_swap_file() {
    local _dir
    for _dir in /tmp/mnt/*; do
        if [ -d "$_dir" ] && [ -f "$_dir/swap.img" ]; then
            SWAP_FILE="$_dir/swap.img"
            return
        fi
    done
}

create_swap() {
    [ -z "$SWAP_FILE" ] && { logecho "Error: SWAP_FILE is not set" error; exit 1; }
    [ -z "$SWAP_SIZE" ] && { logecho "Error: SWAP_SIZE is not set" error; exit 1; }
    grep -Fq "$(readlink -f "$SWAP_FILE")" /proc/swaps && { logecho "Error: Swap file is mounted" error; exit 1; }

    set -e

    logecho "Creating swap file... ($SWAP_SIZE KB)"

    touch "$SWAP_FILE"
    dd if=/dev/zero of="$SWAP_FILE" bs=1k count="$SWAP_SIZE"
    mkswap "$SWAP_FILE"
    chmod 640 "$SWAP_FILE"

    set +e
}

enable_swap() {
    lockfile lockfail || { [ -n "$IS_INTERACTIVE" ] && echo "Already running! ($lockpid)" >&2; exit 1; }

    if ! grep -Fq "file" /proc/swaps; then
        [ -z "$SWAP_FILE" ] && find_swap_file

        if [ -n "$SWAP_FILE" ] && [ -d "$(dirname "$SWAP_FILE")" ] && [ ! -f "$SWAP_FILE" ]; then
            create_swap
        fi

        if [ -f "$SWAP_FILE" ]; then
            if swapon "$SWAP_FILE" ; then
                #shellcheck disable=SC2012
                logecho "Enabled swap file '$SWAP_FILE' ($(/bin/ls -lh "$SWAP_FILE" | awk '{print $5}'))" alert

                if [ -n "$SWAPPINESS" ]; then
                    echo "$SWAPPINESS" > /proc/sys/vm/swappiness
                    logecho "Set swappiness to: $SWAPPINESS" alert
                fi
            else
                logecho "Failed to enable swap on '$SWAP_FILE'" error
            fi
        fi
    fi

    # No matter what the result here is, unset the cron entry if hotplug-event script is available
    execute_script_basename "hotplug-event.sh" check && crontab_entry delete

    lockfile unlock
}

disable_swap() {
    [ -z "$1" ] && return

    local _swap_file="$1"

    sync
    echo 3 > /proc/sys/vm/drop_caches

    if swapoff "$_swap_file" ; then
        logecho "Disabled swap on '$_swap_file'" alert
    else
        logecho "Failed to disable swap on '$_swap_file'" error
    fi
}

case "$1" in
    "run")
        enable_swap
    ;;
    "hotplug")
        if [ "$SUBSYSTEM" = "block" ] && [ -n "$DEVICENAME" ]; then
            case "$ACTION" in
                "add")
                    grep -Fq "file" /proc/swaps && exit 0 # do nothing if swap is already enabled

                    timeout=60
                    while ! df | grep -Fq "/dev/$DEVICENAME" && [ "$timeout" -ge 0 ]; do
                        [ "$timeout" -lt 60 ] && { echo "Device is not yet mounted, waiting 5 seconds..."; sleep 5; }
                        timeout=$((timeout-5))
                    done

                    if df | grep -Fq "/dev/$DEVICENAME"; then
                        enable_swap
                        exit
                    fi

                    [ "$timeout" -le 0 ] && logecho "Device '/dev/$DEVICENAME' did not mount within 60 seconds" error
                ;;
                "remove")
                    # officially multiple swap files are not supported but try to handle it...
                    swap_files=$(grep -F 'file' /proc/swaps | awk '{print $1}')

                    for swap_file in $swap_files; do
                        if [ ! -e "$swap_file" ]; then
                            disable_swap "$swap_file"
                        fi
                    done
                ;;
            esac
        fi
    ;;
    "create")
        [ -n "$2" ] && SWAP_FILE="$2"
        [ -n "$3" ] && SWAP_SIZE="$3"

        create_swap
    ;;
    "start")
        [ "$(nvram get usb_idle_enable)" != "0" ] && { logecho "Error: USB idle timeout is set" error; exit 1; }

        crontab_entry add "*/1 * * * * $script_path run"
        enable_swap
    ;;
    "stop")
        crontab_entry delete

        [ -z "$SWAP_FILE" ] && find_swap_file

        if [ -n "$SWAP_FILE" ] && grep -Fq "$SWAP_FILE" /proc/swaps; then
            disable_swap "$SWAP_FILE"
        fi
    ;;
    "restart")
        sh "$script_path" stop
        sh "$script_path" start
    ;;
    *)
        echo "Usage: $0 run|start|stop|restart|create"
        exit 1
    ;;
esac
