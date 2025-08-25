#!/bin/sh
# Made by Jack'lul <jacklul.github.io>
#
# This script runs fstrim on all mounted SSDs on a schedule
#
# Based on:
#  https://github.com/kuchkovsky/asuswrt-merlin-scripts/blob/main/jffs/scripts/trim_ssd.sh
#  https://github.com/kuchkovsky/asuswrt-merlin-scripts/blob/main/jffs/scripts/ssd_provisioning_mode.sh
#

#jacklul-asuswrt-scripts-update=fstrim.sh
#shellcheck disable=SC2155

readonly script_path="$(readlink -f "$0")"
readonly script_name="$(basename "$script_path" .sh)"
readonly script_dir="$(dirname "$script_path")"
readonly script_config="$script_dir/$script_name.conf"

CRON="0 3 * * 7" # schedule as cron string
CHANGE_PROVISIONING_MODE=false # set provisioning mode to 'unset' for applicable block devices, needed for some storage devices

if [ -f "$script_config" ]; then
    #shellcheck disable=SC1090
    . "$script_config"
fi

lockfile() { #LOCKFILE_START#
    [ -z "$script_name" ] && script_name="$(basename "$0" .sh)"

    _lockfile="/var/lock/script-$script_name.lock"
    _pidfile="/var/run/script-$script_name.pid"
    _fd_min=100
    _fd_max=200

    if [ -n "$2" ]; then
        _lockfile="/var/lock/script-$script_name-$2.lock"
        _pidfile="/var/run/script-$script_name-$2.lock"
    fi

    [ -n "$3" ] && _fd_min="$3" && _fd_max="$3"
    [ -n "$4" ] && _fd_max="$4"

    [ ! -d /var/lock ] && { mkdir -p /var/lock || exit 1; }
    [ ! -d /var/run ] && { mkdir -p /var/run || exit 1; }

    _lockpid=
    [ -f "$_pidfile" ] && _lockpid="$(cat "$_pidfile")"

    case "$1" in
        "lockwait"|"lockfail"|"lockexit")
            for _fd_test in "/proc/$$/fd"/*; do
                if [ "$(readlink -f "$_fd_test")" = "$_lockfile" ]; then
                    logger -st "$script_name" "File descriptor ($(basename "$_fd_test")) is already open for the same lockfile ($_lockfile)"
                    exit 1
                fi
            done

            _fd=$(lockfile_fd "$_fd_min" "$_fd_max")
            eval exec "$_fd>$_lockfile"

            case "$1" in
                "lockwait")
                    _lockwait=0
                    while ! flock -nx "$_fd"; do
                        eval exec "$_fd>&-"
                        _lockwait=$((_lockwait+1))

                        if [ "$_lockwait" -ge 60 ]; then
                            logger -st "$script_name" "Failed to acquire a lock after 60 seconds ($_lockfile)"
                            exit 1
                        fi

                        sleep 1
                        _fd=$(lockfile_fd "$_fd_min" "$_fd_max")
                        eval exec "$_fd>$_lockfile"
                    done
                ;;
                "lockfail")
                    flock -nx "$_fd" || return 1
                ;;
                "lockexit")
                    flock -nx "$_fd" || exit 1
                ;;
            esac

            echo $$ > "$_pidfile"
            chmod 644 "$_pidfile"
            trap 'flock -u $_fd; rm -f "$_lockfile" "$_pidfile"; exit $?' INT TERM EXIT
        ;;
        "unlock")
            flock -u "$_fd"
            eval exec "$_fd>&-"
            rm -f "$_lockfile" "$_pidfile"
            trap - INT TERM EXIT
        ;;
        "check")
            [ -n "$_lockpid" ] && [ -f "/proc/$_lockpid/stat" ] && return 0
            return 1
        ;;
        "kill")
            [ -n "$_lockpid" ] && [ -f "/proc/$_lockpid/stat" ] && kill -9 "$_lockpid" && return 0
            return 1
        ;;
    esac
}

lockfile_fd() {
    _lfd_min=$1
    _lfd_max=$2

    while [ -f "/proc/$$/fd/$_lfd_min" ]; do
        _lfd_min=$((_lfd_min+1))
        [ "$_lfd_min" -gt "$_lfd_max" ] && { logger -st "$script_name" "Error: No free file descriptors available"; exit 1; }
    done

    echo "$_lfd_min"
} #LOCKFILE_END#

is_valid_ssd_device() {
    [ ! -d "/sys/block/$1" ] && { echo "Device not found: /sys/block/$1"; return 1; }

    _dev="/sys/block/$1"

    # Check if device is SSD
    rotational=$(cat "$dev/queue/rotational" 2>/dev/null || echo "N/A")
    if [ "$rotational" != "0" ]; then
        echo "Device is not an SSD: $_dev"
        return 1
    fi

    # Check if TRIM is supported
    max_discard=$(cat "$dev/queue/discard_max_hw_bytes" 2>/dev/null || echo "N/A")
    if [ "$max_discard" = "N/A" ] || [ "$max_discard" -eq 0 ]; then
        echo "Device does not support discard: $_dev"
        return 1
    fi

    return 0
}

change_provisioning_mode() {
    [ ! -d "/sys/block/$1" ] && { echo "Device not found: /sys/block/$1"; return; }

    # Set provisioning_mode to 'unmap' to allow TRIM commands to go through
    find "/sys/block/$1/device" -type f -name "provisioning_mode" | while read -r file; do
        [ -z "$file" ] && continue

        _contents=$(cat "$file" 2>/dev/null || echo "")

        if [ "$_contents" != "unmap" ]; then
            echo "Writing 'unmap' to $file"
            echo "unmap" > "$file"
        fi
    done
}

case "$1" in
    "run")
        [ -z "$(which fstrim 2>/dev/null)" ] && { logger -st "$script_name" "Error: Command 'fstrim' not found"; exit 1; }

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

                    #shellcheck disable=SC2181
                    if [ $? -ne 0 ]; then
                        log="/tmp/fstrim_$name.log"
                        #shellcheck disable=SC3037
                        echo -e "$output" > "$log"
                        logger -st "$script_name" "fstrim error on $mount_device - check $log for details"
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
        [ -z "$(which fstrim 2>/dev/null)" ] && { echo "Warning: Command 'fstrim' not found"; }

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
