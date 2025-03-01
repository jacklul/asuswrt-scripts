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

readonly SCRIPT_PATH="$(readlink -f "$0")"
readonly SCRIPT_NAME="$(basename "$SCRIPT_PATH" .sh)"
readonly SCRIPT_DIR="$(dirname "$SCRIPT_PATH")"
readonly SCRIPT_CONFIG="$SCRIPT_DIR/$SCRIPT_NAME.conf"
readonly SCRIPT_TAG="$(basename "$SCRIPT_PATH")"

SWAP_FILE="" # swap file path, like /tmp/mnt/USBDEVICE/swap.img, leave empty to search for it in /tmp/mnt/*/swap.img
SWAP_SIZE=524288 # swap file size, changing after swap is created requires it to be manually removed, 524288 = 512MB
SWAPPINESS= # change the value of vm.swappiness (/proc/sys/vm/swappiness), if left empty it will not be changed
RUN_EVERY_MINUTE= # check for new devices to mount swap on periodically (true/false), empty means false when hotplug-event.sh is available but otherwise true

if [ -f "$SCRIPT_CONFIG" ]; then
    #shellcheck disable=SC1090
    . "$SCRIPT_CONFIG"
fi

if [ -z "$RUN_EVERY_MINUTE" ]; then
    [ ! -x "$SCRIPT_DIR/hotplug-event.sh" ] && RUN_EVERY_MINUTE=true
fi

lockfile() { #LOCKFILE_START#
    _LOCKFILE="/var/lock/script-$SCRIPT_NAME.lock"
    _PIDFILE="/var/run/script-$SCRIPT_NAME.pid"
    _FD=100
    _FD_MAX=200

    if [ -n "$2" ]; then
        _LOCKFILE="/var/lock/script-$SCRIPT_NAME-$2.lock"
        _PIDFILE="/var/run/script-$SCRIPT_NAME-$2.lock"
    fi

    [ -n "$3" ] && [ "$3" -eq "$3" ] && _FD="$3" && _FD_MAX="$3"
    [ -n "$4" ] && [ "$4" -eq "$4" ] && _FD_MAX="$4"

    [ ! -d /var/lock ] && mkdir -p /var/lock
    [ ! -d /var/run ] && mkdir -p /var/run

    _LOCKPID=
    [ -f "$_PIDFILE" ] && _LOCKPID="$(cat "$_PIDFILE")"

    case "$1" in
        "lockwait"|"lockfail"|"lockexit")
            while [ -f "/proc/$$/fd/$_FD" ]; do
                #echo "File descriptor $_FD is already in use ($(readlink -f "/proc/$$/fd/$_FD"))"
                _FD=$((_FD+1))

                [ "$_FD" -gt "$_FD_MAX" ] && { echo "Failed to find available file descriptor"; exit 1; }
            done

            eval exec "$_FD>$_LOCKFILE"

            case "$1" in
                "lockwait")
                    _LOCK_WAITED=0
                    while ! flock -nx "$_FD"; do #flock -x "$_FD"
                        sleep 1
                        if [ "$_LOCK_WAITED" -ge 60 ]; then
                            echo "Failed to acquire a lock after 60 seconds"
                            exit 1
                        fi
                    done
                ;;
                "lockfail")
                    flock -nx "$_FD" || return 1
                ;;
                "lockexit")
                    flock -nx "$_FD" || exit 1
                ;;
            esac

            echo $$ > "$_PIDFILE"
            trap 'flock -u $_FD; rm -f "$_LOCKFILE" "$_PIDFILE"; exit $?' INT TERM EXIT
        ;;
        "unlock")
            flock -u "$_FD"
            rm -f "$_LOCKFILE" "$_PIDFILE"
            trap - INT TERM EXIT
        ;;
        "check")
            [ -n "$_LOCKPID" ] && [ -f "/proc/$_LOCKPID/stat" ] && return 0
            return 1
        ;;
        "kill")
            [ -n "$_LOCKPID" ] && [ -f "/proc/$_LOCKPID/stat" ] && kill -9 "$_LOCKPID" && return 0
            return 1
        ;;
    esac
} #LOCKFILE_END#

find_swap_file() {
    for _DIR in /tmp/mnt/*; do
        if [ -d "$_DIR" ] && [ -f "$_DIR/swap.img" ]; then
            SWAP_FILE="$_DIR/swap.img"
            return
        fi
    done
}

disable_swap() {
    [ -z "$1" ] && return

    _SWAP_FILE="$1"

    sync
    echo 3 > /proc/sys/vm/drop_caches

    if swapoff "$SWAP_FILE" ; then
        logger -st "$SCRIPT_TAG" "Disabled swap on '$SWAP_FILE'"
    else
        logger -st "$SCRIPT_TAG" "Failed to disable swap on '$SWAP_FILE'"
    fi
}

case "$1" in
    "run")
        lockfile lockfail || { echo "Already running! ($_LOCKPID)"; exit 1; }

        if ! grep -q "file" /proc/swaps; then
            [ -z "$SWAP_FILE" ] && find_swap_file

            if [ -n "$SWAP_FILE" ] && [ -d "$(dirname "$SWAP_FILE")" ] && [ ! -f "$SWAP_FILE" ]; then
                sh "$SCRIPT_PATH" create
            fi

            if [ -f "$SWAP_FILE" ]; then
                if swapon "$SWAP_FILE" ; then
                    #shellcheck disable=SC2012
                    logger -st "$SCRIPT_TAG" "Enabled swap file '$SWAP_FILE' ($(ls -hs "$SWAP_FILE" | awk '{print $1}'))"

                    if [ -n "$SWAPPINESS" ]; then
                        echo "$SWAPPINESS" > /proc/sys/vm/swappiness
                        logger -st "$SCRIPT_TAG" "Set swappiness to $SWAPPINESS"
                    fi
                else
                    logger -st "$SCRIPT_TAG" "Failed to enable swap on '$SWAP_FILE'"
                fi
            fi
        fi

        lockfile unlock
    ;;
    "hotplug")
        if [ "$(echo "$DEVICENAME" | cut -c 1-2)" = "sd" ]; then
            case "$ACTION" in
                "add")
                    grep -q "file" /proc/swaps && exit 0 # do nothing if swap is already enabled

                    TIMEOUT=60
                    while ! df | grep -q "/dev/$DEVICENAME" && [ "$TIMEOUT" -ge 0 ]; do
                        [ "$TIMEOUT" -lt 60 ] && { echo "Device is not yet mounted, waiting 5 seconds..."; sleep 5; }

                        TIMEOUT=$((TIMEOUT-5))
                    done

                    if df | grep -q "/dev/$DEVICENAME"; then
                        sh "$SCRIPT_PATH" run
                        exit
                    fi

                    [ "$TIMEOUT" -le 0 ] && echo "Device /dev/$DEVICENAME did not mount within 60 seconds"
                ;;
                "remove")
                    # officially multiple swap files are not supported but try to handle it...
                    SWAP_FILES=$(grep 'file' /proc/swaps | awk '{print $1}')

                    for SWAP_FILE in $SWAP_FILES; do
                        # in theory this should not work as df won't return unmounted filesystems?
                        SWAP_FILE_DEVICE="$(df "$SWAP_FILE" | tail -1 | awk '{print $1}')"

                        if [ "$SWAP_FILE_DEVICE" = "/dev/$DEVICENAME" ]; then
                            disable_swap "$SWAP_FILE"
                        fi
                    done
                ;;
                *)
                    logger -st "$SCRIPT_TAG" "Unknown hotplug action: $ACTION ($DEVICENAME)"
                    exit 1
                ;;
            esac
        fi
    ;;
    "create")
        [ -n "$2" ] && SWAP_FILE="$2"
        [ -n "$3" ] && SWAP_SIZE="$3"

        [ -z "$SWAP_FILE" ] && { logger -st "$SCRIPT_TAG" "Swap file is not set"; exit 1; }
        [ -z "$SWAP_SIZE" ] && { logger -st "$SCRIPT_TAG" "Swap size is not set"; exit 1; }

        set -e

        echo "Creating swap file..."
        touch "$SWAP_FILE"
        dd if=/dev/zero of="$SWAP_FILE" bs=1k count="$SWAP_SIZE"
        mkswap "$SWAP_FILE"

        set +e
    ;;
    "start")
        if [ "$(nvram get usb_idle_enable)" != "0" ]; then
            logger -st "$SCRIPT_TAG" "Unable to enable swap - USB Idle timeout is set"
            exit 1
        fi

        if [ -x "$SCRIPT_DIR/cron-queue.sh" ]; then
            sh "$SCRIPT_DIR/cron-queue.sh" add "$SCRIPT_NAME" "$SCRIPT_PATH run"
        else
            cru a "$SCRIPT_NAME" "*/1 * * * * $SCRIPT_PATH run"
        fi

        sh "$SCRIPT_PATH" run
    ;;
    "stop")
        [ -x "$SCRIPT_DIR/cron-queue.sh" ] && sh "$SCRIPT_DIR/cron-queue.sh" remove "$SCRIPT_NAME"
        cru d "$SCRIPT_NAME"

        [ -z "$SWAP_FILE" ] && find_swap_file

        if [ -n "$SWAP_FILE" ] && grep -q "$SWAP_FILE" /proc/swaps; then
            disable_swap "$SWAP_FILE"
        fi
    ;;
    "restart")
        sh "$SCRIPT_PATH" stop
        sh "$SCRIPT_PATH" start
    ;;
    *)
        echo "Usage: $0 run|start|stop|restart|create"
        exit 1
    ;;
esac
