#!/bin/sh
# Made by Jack'lul <jacklul.github.io>
#
# Setup and enable swap file on startup
#
# Based on:
#  https://github.com/decoderman/amtm/blob/master/amtm_modules/swap.mod
#

#jacklul-asuswrt-scripts-update=swap.sh
#shellcheck disable=SC2155

readonly script_path="$(readlink -f "$0")"
readonly script_name="$(basename "$script_path" .sh)"
readonly script_dir="$(dirname "$script_path")"
readonly script_config="$script_dir/$script_name.conf"

SWAP_FILE="" # swap file path, like /tmp/mnt/USBDEVICE/swap.img, leave empty to search for it in /tmp/mnt/*/swap.img
SWAP_SIZE=1048576 # swap file size, changing after swap is created requires it to be manually removed, 1048576 = 1GB
SWAPPINESS= # change the value of vm.swappiness (/proc/sys/vm/swappiness), if left empty it will not be changed
RUN_EVERY_MINUTE= # check for new devices to mount swap on periodically (true/false), empty means false when hotplug-event.sh is available but otherwise true

if [ -f "$script_config" ]; then
    #shellcheck disable=SC1090
    . "$script_config"
fi

if [ -z "$RUN_EVERY_MINUTE" ]; then
    [ ! -x "$script_dir/hotplug-event.sh" ] && RUN_EVERY_MINUTE=true
fi

lockfile() { #LOCKFILE_START#
    [ -z "$script_name" ] && script_name="$(basename "$0" .sh)"

    _lockfile="/var/lock/script-$script_name.lock"
    _pidfile="/var/run/script-$script_name.pid"
    _fd=100
    _fd_max=200

    if [ -n "$2" ]; then
        _lockfile="/var/lock/script-$script_name-$2.lock"
        _pidfile="/var/run/script-$script_name-$2.lock"
    fi

    [ -n "$3" ] && [ "$3" -eq "$3" ] && _fd="$3" && _fd_max="$3"
    [ -n "$4" ] && [ "$4" -eq "$4" ] && _fd_max="$4"

    [ ! -d /var/lock ] && { mkdir -p /var/lock || exit 1; }
    [ ! -d /var/run ] && { mkdir -p /var/run || exit 1; }

    _lockpid=
    [ -f "$_pidfile" ] && _lockpid="$(cat "$_pidfile")"

    case "$1" in
        "lockwait"|"lockfail"|"lockexit")
            while [ -f "/proc/$$/fd/$_fd" ]; do
                _fd=$((_fd+1))
                [ "$_fd" -gt "$_fd_max" ] && { logger -st "$script_name" "No free file descriptors available"; exit 1; }
            done

            eval exec "$_fd>$_lockfile"

            case "$1" in
                "lockwait")
                    _lockwait=0
                    while ! flock -nx "$_fd"; do # flock -x "$_fd" sometimes gets stuck
                        sleep 1
                        if [ "$_lockwait" -ge 60 ]; then
                            logger -st "$script_name" "Failed to acquire a lock after 60 seconds"
                            exit 1
                        fi
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
} #LOCKFILE_END#

find_swap_file() {
    for _dir in /tmp/mnt/*; do
        if [ -d "$_dir" ] && [ -f "$_dir/swap.img" ]; then
            SWAP_FILE="$_dir/swap.img"
            return
        fi
    done
}

disable_swap() {
    [ -z "$1" ] && return

    _swap_file="$1"

    sync
    echo 3 > /proc/sys/vm/drop_caches

    if swapoff "$_swap_file" ; then
        logger -st "$script_name" "Disabled swap on '$_swap_file'"
    else
        logger -st "$script_name" "Failed to disable swap on '$_swap_file'"
    fi
}

case "$1" in
    "run")
        lockfile lockfail || { echo "Already running! ($_lockpid)"; exit 1; }

        if ! grep -Fq "file" /proc/swaps; then
            [ -z "$SWAP_FILE" ] && find_swap_file

            if [ -n "$SWAP_FILE" ] && [ -d "$(dirname "$SWAP_FILE")" ] && [ ! -f "$SWAP_FILE" ]; then
                sh "$script_path" create
            fi

            if [ -f "$SWAP_FILE" ]; then
                if swapon "$SWAP_FILE" ; then
                    #shellcheck disable=SC2012
                    logger -st "$script_name" "Enabled swap file '$SWAP_FILE' ($(/bin/ls -lh "$SWAP_FILE" | awk '{print $5}'))"

                    if [ -n "$SWAPPINESS" ]; then
                        echo "$SWAPPINESS" > /proc/sys/vm/swappiness
                        logger -st "$script_name" "Set swappiness to $SWAPPINESS"
                    fi
                else
                    logger -st "$script_name" "Failed to enable swap on '$SWAP_FILE'"
                fi
            fi
        fi

        lockfile unlock
    ;;
    "hotplug")
        if [ "$(echo "$DEVICENAME" | cut -c 1-2)" = "sd" ]; then
            case "$ACTION" in
                "add")
                    grep -Fq "file" /proc/swaps && exit 0 # do nothing if swap is already enabled

                    timeout=60
                    while ! df | grep -Fq "/dev/$DEVICENAME" && [ "$timeout" -ge 0 ]; do
                        [ "$timeout" -lt 60 ] && { echo "Device is not yet mounted, waiting 5 seconds..."; sleep 5; }
                        timeout=$((timeout-5))
                    done

                    if df | grep -Fq "/dev/$DEVICENAME"; then
                        sh "$script_path" run
                        exit
                    fi

                    [ "$timeout" -le 0 ] && logger -st "$script_name" "Device /dev/$DEVICENAME did not mount within 60 seconds"
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

        [ -z "$SWAP_FILE" ] && { logger -st "$script_name" "Swap file is not set"; exit 1; }
        [ -z "$SWAP_SIZE" ] && { logger -st "$script_name" "Swap size is not set"; exit 1; }

        set -e

        echo "Creating swap file... ($SWAP_SIZE KB)"
        touch "$SWAP_FILE"
        dd if=/dev/zero of="$SWAP_FILE" bs=1k count="$SWAP_SIZE"
        mkswap "$SWAP_FILE"
        chmod 640 "$SWAP_FILE"

        set +e
    ;;
    "start")
        if [ "$(nvram get usb_idle_enable)" != "0" ]; then
            logger -st "$script_name" "Unable to enable swap - USB Idle timeout is set"
            exit 1
        fi

        if [ -x "$script_dir/cron-queue.sh" ]; then
            sh "$script_dir/cron-queue.sh" add "$script_name" "$script_path run"
        else
            cru a "$script_name" "*/1 * * * * $script_path run"
        fi

        sh "$script_path" run
    ;;
    "stop")
        [ -x "$script_dir/cron-queue.sh" ] && sh "$script_dir/cron-queue.sh" remove "$script_name"
        cru d "$script_name"

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
