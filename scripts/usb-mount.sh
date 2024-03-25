#!/bin/sh
# Made by Jack'lul <jacklul.github.io>
#
# Automatically mounts any USB storage
#

# jacklul-asuswrt-scripts-update
#shellcheck disable=SC2155

readonly SCRIPT_PATH="$(readlink -f "$0")"
readonly SCRIPT_NAME="$(basename "$SCRIPT_PATH" .sh)"
readonly SCRIPT_DIR="$(dirname "$SCRIPT_PATH")"
readonly SCRIPT_CONFIG="$SCRIPT_DIR/$SCRIPT_NAME.conf"
readonly SCRIPT_TAG="$(basename "$SCRIPT_PATH")"

EXECUTE_COMMAND="" # execute a command each time status changes (receives arguments: $1 = action, $2 = device)

if [ -f "$SCRIPT_CONFIG" ]; then
    #shellcheck disable=SC1090
    . "$SCRIPT_CONFIG"
fi

if [ -z "$MOUNT_DEVICE" ]; then
    for DEVICE in /dev/sd*; do
        if [ -b "$DEVICE" ]; then
            MOUNT_DEVICE=$DEVICE
            break
        fi
    done
fi

lockfile() { #LOCKFILE_START#
    _LOCKFILE="/var/lock/script-$SCRIPT_NAME.lock"
    _PIDFILE="/var/run/script-$SCRIPT_NAME.pid"
    _FD=100

    if [ -n "$2" ]; then
        _LOCKFILE="/var/lock/script-$SCRIPT_NAME-$2.lock"
        _PIDFILE="/var/run/script-$SCRIPT_NAME-$2.lock"
    fi

    [ -n "$3" ] && [ "$3" -eq "$3" ] && _FD="$3"

    _LOCKPID=
    [ -f "$_PIDFILE" ] && _LOCKPID="$(cat "$_PIDFILE")"

    case "$1" in
        "lockwait"|"lockfail"|"lockexit")
            if [ -f "/proc/$$/fd/$_FD" ]; then
                echo "File descriptor $_FD is already in use ($(readlink -f "/proc/$$/fd/$_FD"))"
                exit 1
            fi

            eval exec "$_FD>$_LOCKFILE"

            case "$1" in
                "lockwait")
                    flock -x "$_FD"
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

is_asusware_mounting() {
    _APPS_AUTORUN="$(nvram get apps_state_autorun)"

    if [ "$_APPS_AUTORUN" != "" ] && [ "$_APPS_AUTORUN" != "4" ]; then
        _VARS_TO_CHECK="apps_state_install apps_state_remove apps_state_switch apps_state_stop apps_state_enable apps_state_update apps_state_upgrade apps_state_cancel apps_state_error"

        for _VAR in $_VARS_TO_CHECK; do
            _VALUE="$(nvram get "$_VAR")"

            if [ "$_VALUE" != "" ] && [ "$_VALUE" != "0" ]; then
                return 1
            fi
        done

        return 0
    fi

    return 1
}

setup_mount() {
    [ -z "$2" ] && { echo "You must specify a device"; exit 1; }

    if is_asusware_mounting; then
        logger -st "$SCRIPT_TAG" "Ignoring call because Asusware is mounting (args: \"$1\" \"$2\")"
        exit
    fi

    lockfile lockwait

    _DEVICE="/dev/$2"
    _MOUNTPOINT="/tmp/mnt/$2"

    case "$1" in
        "add")
            [ ! -b "$_DEVICE" ] && return

            if ! mount | grep -q "$_MOUNTPOINT"; then
                mkdir -p "$_MOUNTPOINT"

                #shellcheck disable=SC2086
                if mount "$_DEVICE" "$_MOUNTPOINT"; then
                    logger -st "$SCRIPT_TAG" "Mounted $_DEVICE on $_MOUNTPOINT"
                else
                    rmdir "$_MOUNTPOINT"
                    logger -st "$SCRIPT_TAG" "Failed to mount $_DEVICE on $_MOUNTPOINT"
                fi
            fi
        ;;
        "remove")
            if mount | grep -q "$_MOUNTPOINT"; then
                if [ "$(mount | grep -c "$_DEVICE")" -gt "1" ]; then
                    logger -st "$SCRIPT_TAG" "Unable to unmount $_MOUNTPOINT - device $_DEVICE is used by another mount"
                else
                    if umount "$_MOUNTPOINT"; then
                        rmdir "$_MOUNTPOINT"
                        logger -st "$SCRIPT_TAG" "Unmounted $_DEVICE from $_MOUNTPOINT"
                    else
                        logger -st "$SCRIPT_TAG" "Failed to unmount $_DEVICE from $_MOUNTPOINT"
                    fi
                fi
            fi
        ;;
    esac

    [ -n "$EXECUTE_COMMAND" ] && $EXECUTE_COMMAND "$1" "$_DEVICE"

    lockfile unlock
}

case "$1" in
    "run")
        for DEVICE in /dev/sd*; do
            [ ! -b "$DEVICE" ] && continue

            DEVICENAME="$(basename "$DEVICE")"

            if [ ! -d "/tmp/mnt/$DEVICENAME" ]; then
                setup_mount add "$DEVICENAME"
            fi
        done
    ;;
    "hotplug")
        if [ "$(echo "$DEVICENAME" | cut -c 1-2)" = "sd" ]; then
            case "$ACTION" in
                "add")
                    setup_mount add "$DEVICENAME"
                ;;
                "remove")
                    setup_mount remove "$DEVICENAME"
                ;;
                *)
                    logger -st "$SCRIPT_TAG" "Unknown hotplug action: $ACTION ($DEVICENAME)"
                    exit 1
                ;;
            esac
        fi
    ;;
    "start")
        if [ -x "$SCRIPT_DIR/cron-queue.sh" ]; then
            sh "$SCRIPT_DIR/cron-queue.sh" add "$SCRIPT_NAME" "$SCRIPT_PATH run"
        else
            cru a "$SCRIPT_NAME" "*/1 * * * * $SCRIPT_PATH run"
        fi

        for DEVICE in /dev/sd*; do
            [ -b "$DEVICE" ] && setup_mount add "$(basename "$DEVICE")"
        done
    ;;
    "stop")
        [ -x "$SCRIPT_DIR/cron-queue.sh" ] && sh "$SCRIPT_DIR/cron-queue.sh" remove "$SCRIPT_NAME"
        cru d "$SCRIPT_NAME"

        for DEVICE in /dev/sd*; do
            [ -b "$DEVICE" ] && setup_mount remove "$(basename "$DEVICE")"
        done
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
