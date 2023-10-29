#!/bin/sh
# Made by Jack'lul <jacklul.github.io>
#
# Automatically mounts any USB storage
#

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

lockfile() { #LOCKFUNC_START#
    _LOCKFILE="/tmp/$SCRIPT_NAME.lock"

    case "$1" in
        "lock")
            if [ -f "$_LOCKFILE" ]; then
                _LOCKWAITLIMIT=60
                _LOCKWAITTIMER=0
                while [ "$_LOCKWAITTIMER" -lt "$_LOCKWAITLIMIT" ]; do
                    [ ! -f "$_LOCKFILE" ] && break

                    _LOCKPID="$(sed -n '1p' "$_LOCKFILE")"
                    _LOCKCMD="$(sed -n '2p' "$_LOCKFILE")"

                    [ ! -d "/proc/$_LOCKPID" ] && break;
                    [ "$_LOCKPID" = "$$" ] && break;

                    _LOCKWAITTIMER=$((_LOCKWAITTIMER+1))
                    sleep 1
                done

                [ "$_LOCKWAITTIMER" -ge "$_LOCKWAITLIMIT" ] && { logger -st "$SCRIPT_TAG" "Unable to obtain lock after $_LOCKWAITLIMIT seconds, held by $_LOCKPID ($_LOCKCMD)"; exit 1; }
            fi

            echo "$$" > "$_LOCKFILE"
            echo "$@" >> "$_LOCKFILE"
            trap 'rm -f "$_LOCKFILE"; exit $?' EXIT
        ;;
        "unlock")
            if [ -f "$_LOCKFILE" ]; then
                _LOCKPID="$(sed -n '1p' "$_LOCKFILE")"

                if [ -d "/proc/$_LOCKPID" ] && [ "$_LOCKPID" != "$$" ]; then
                    echo "Attempted to remove not own lock"
                    exit 1
                fi

                rm -f "$_LOCKFILE"
            fi

            trap - EXIT
        ;;
    esac
} #LOCKFUNC_END#

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

    lockfile lock

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
        cru a "$SCRIPT_NAME" "*/1 * * * * $SCRIPT_PATH run"

        for DEVICE in /dev/sd*; do
            [ -b "$DEVICE" ] && setup_mount add "$(basename "$DEVICE")"
        done
    ;;
    "stop")
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
