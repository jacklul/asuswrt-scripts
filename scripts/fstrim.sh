#!/bin/sh
# Made by Jack'lul <jacklul.github.io>
#
# Run fstrim on all mounted SSDs on a schedule
#
# Based on:
#  https://github.com/kuchkovsky/asuswrt-merlin-scripts?#5-automatic-usb-ssd-trimming
#  https://github.com/gitbls/sdm/blob/master/satrim
#

#jas-update=fstrim.sh
#shellcheck disable=SC2155
#shellcheck source=./common.sh
readonly common_script="$(dirname "$0")/common.sh"
if [ -f "$common_script" ]; then . "$common_script"; else { echo "$common_script not found"; exit 1; } fi

CRON="0 3 * * 7" # schedule as cron string
CHANGE_PROVISIONING_MODE=false # set provisioning mode to 'unset' for applicable block devices, needed for some storage devices
CHANGE_DISCARD_MAX_BYTES=false # automatically set discard_max_bytes to the correct value, requires 'sg_vpd' command (Entware's 'sg3_utils' package)
FILTER_IDVENDOR="" # only affect devices with specific idVendor values, separated by spaces
FILTER_IDPRODUCT="" # only affect devices with specific idProduct values, separated by spaces

load_script_config

is_ssd_device_name() {
    [ "$(echo "$1" | cut -c 1-2)" = "sd" ] && return 0
    [ "$(echo "$1" | cut -c 1-4)" = "nvme" ] && return 0
    [ "$(echo "$1" | cut -c 1-6)" = "mmcblk" ] && return 0
    return 1
}

filter_device() {
    _idVendor="$1"
    _idProduct="$2"
    _match_idVendor=
    _match_idProduct=

    if [ -n "$FILTER_IDVENDOR" ]; then
        for _filter in $FILTER_IDVENDOR; do
            [ "$_idVendor" = "$_filter" ] && _match_idVendor=true && break
        done
    fi

    if [ -n "$FILTER_IDPRODUCT" ]; then
        for _filter in $FILTER_IDPRODUCT; do
            [ "$_idProduct" = "$_filter" ] && _match_idProduct=true && break
        done
    fi

    if [ -n "$FILTER_IDVENDOR" ] && [ -n "$FILTER_IDPRODUCT" ]; then
        if [ -n "$_match_idVendor" ] && [ -n "$_match_idProduct" ]; then
            return 0
        fi
    elif [ -n "$_match_idVendor" ] || [ -n "$_match_idProduct" ]; then
        return 0
    fi

    return 1
}

is_valid_ssd_device() {
    [ -z "$1" ] && { echo "Device name not provided"; return 1; }
    [ ! -d "/sys/block/$1" ] && { echo "Device not found: /sys/block/$1"; return 1; }

    _dev="/sys/block/$1"

    if [ -n "$FILTER_IDVENDOR" ] || [ -n "$FILTER_IDPRODUCT" ]; then
        _idVendor=
        _idProduct=
        _search_path="$(readlink -f "$_dev/device")"

        # Search recursively for idVendor/idProduct
        _depth=10
        while [ "$_depth" -gt 0 ]; do
            [ -f "$_search_path/idVendor" ] && _idVendor="$(cat "$_search_path/idVendor")"
            [ -f "$_search_path/idProduct" ] && _idProduct="$(cat "$_search_path/idProduct")"
            [ -n "$_idVendor" ] && [ -n "$_idProduct" ] && break
            _search_path="$(dirname "$_search_path")"
            [ "$_search_path" = /sys/devices ] && break
            _depth=$((_depth-1))
        done

        if ! filter_device "$_idVendor" "$_idProduct"; then
            echo "Device does not match filtering rules: $_dev"
            return 1
        fi
    fi

    # Check if device is SSD
    _rotational=$(cat "$dev/queue/rotational" 2> /dev/null || echo "N/A")
    if [ "$_rotational" != "0" ]; then
        echo "Device is not an SSD: $_dev"
        return 1
    fi

    # Check if TRIM is supported
    _max_discard=$(cat "$dev/queue/discard_max_hw_bytes" 2> /dev/null || echo "N/A")
    case "$_max_discard" in
        ''|0|*[!0-9]*)
            echo "Device does not support discard: $_dev"
            return 1
        ;;
    esac

    return 0
}

change_provisioning_mode() {
    [ -z "$1" ] && { echo "Device name not provided"; return 1; }
    [ ! -d "/sys/block/$1" ] && { echo "Device not found: /sys/block/$1"; return 1; }

    if type sg_vpd > /dev/null 2>&1; then
        _unmap_supported="$(sg_vpd -p lbpv "/dev/$1" | grep "Unmap command supported" | cut -d ': ' -f 2)"

        if [ "$_unmap_supported" != "1" ]; then
            echo "Unmap command is not supported on device: /sys/block/$1"
            return 1
        fi
    fi

    # Set provisioning_mode to 'unmap' to allow TRIM commands to go through
    find "/sys/block/$1/device" -type f -name "provisioning_mode" | while read -r _file; do
        [ -z "$_file" ] && continue

        _contents=$(cat "$_file" 2> /dev/null || echo "")

        if [ "$_contents" != "unmap" ]; then
            echo "Writing 'unmap' to '$_file'"
            echo "unmap" > "$_file"
        fi
    done
}

change_discard_max_bytes() {
    [ -z "$1" ] && { echo "Device name not provided"; return 1; }
    [ ! -d "/sys/block/$1" ] && { echo "Device not found: /sys/block/$1"; return 1; }

    if ! type sg_vpd > /dev/null 2>&1 || ! type sg_readcap > /dev/null 2>&1; then
        logecho "Missing required commands ('sg_vpd', 'sg_readcap')"
        return 0
    fi

    _lba_count="$(sg_vpd -p bl "/dev/$1" | grep "Maximum unmap LBA count" | cut -d ': ' -f 2)"
    _block_length="$(cat "/sys/block/$1/queue/logical_block_size")"
    _value=$((_lba_count *_block_length))
    _file="/sys/block/$1/queue/discard_max_bytes"
    _contents=$(cat "$_file" 2> /dev/null || echo "")

    if [ "$_contents" != "$_value" ]; then
        _discard_granularity="$(cat "/sys/block/$1/queue/discard_granularity")"
        if [ "$((_value % _discard_granularity))" -ne 0 ]; then
            logecho "Calculated value is not divisible by discard_granularity (/sys/block/$1)"
            return 1
        fi

        _discard_max_hw_bytes="$(cat "/sys/block/$1/queue/discard_max_hw_bytes")"
        if [ "$_value" -gt "$_discard_max_hw_bytes" ]; then
            logecho "Calculated value exceeded discard_max_hw_bytes (/sys/block/$1)"
            return 1
        fi

        echo "Writing '$_value' to '$_file'"
        echo "$_value" > "$_file"
    fi
}

process_device() {
    [ -z "$1" ] && { echo "Device name not provided"; return 1; }

    is_valid_ssd_device "$1" || return 1
    [ "$CHANGE_PROVISIONING_MODE" = true ] && { change_provisioning_mode "$1" || return 1; }
    [ "$CHANGE_DISCARD_MAX_BYTES" = true ] && { change_discard_max_bytes "$1" || return 1; }
}

case "$1" in
    "run")
        type fstrim > /dev/null 2>&1 || { logecho "Error: Command 'fstrim' not found"; exit 1; }

        lockfile lockfail

        for dev in /sys/block/*; do
            name=$(basename "$dev")

            if is_ssd_device_name "$name"; then
                is_valid_ssd_device "$name" || continue
                [ "$CHANGE_PROVISIONING_MODE" = true ] && { change_provisioning_mode "$name" || continue; }
                [ "$CHANGE_DISCARD_MAX_BYTES" = true ] && { change_discard_max_bytes "$name" || continue; }

                trimmed=""
                mount | grep "/dev/$name" | while read -r line; do
                    mount_device="$(echo "$line" | awk '{print $1}')"
                    mount_point="$(echo "$line" | awk '{print $3}')"

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
                        logecho "Executed fstrim on '$mount_device': $(echo "$output" | tr '\n' ' ')" true
                    else
                        logecho "Failed to execute fstrim on '$mount_device': $(echo "$output" | tr '\n' ' ')"
                    fi
                done
            fi
        done

        lockfile unlock
    ;;
    "hotplug")
        if [ "$SUBSYSTEM" = "block" ] && [ -n "$DEVICENAME" ]; then
            case "$ACTION" in
                "add")
                    process_device "$DEVICENAME"
                ;;
            esac
        fi
    ;;
    "start")
        type fstrim > /dev/null 2>&1 || echo "Warning: Command 'fstrim' not found"

        for dev in /sys/block/*; do
            name=$(basename "$dev")
            is_ssd_device_name "$name" && process_device "$name"
        done

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
