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

setup_mount() {
    [ -z "$2" ] && { echo "You must specify a device"; exit 1; }

    _DEVICE="/dev/$2"
    _MOUNTPOINT="/tmp/mnt/$2"

    case "$1" in
        "add")
            [ ! -b "$_DEVICE" ] && return

            if ! mount | grep -q "$_MOUNTPOINT"; then
                mkdir -p "$_MOUNTPOINT"
                
                #shellcheck disable=SC2086
                if mount "$_DEVICE" "$_MOUNTPOINT"; then
                    logger -s -t "$SCRIPT_TAG" "Mounted $_DEVICE on $_MOUNTPOINT"
                else
                    rmdir "$_MOUNTPOINT"
                    logger -s -t "$SCRIPT_TAG" "Failed to mount $_DEVICE on $_MOUNTPOINT"
                fi
            fi
        ;;
        "remove")
            if mount | grep -q "$_MOUNTPOINT"; then
                if umount "$_MOUNTPOINT"; then
                    rmdir "$_MOUNTPOINT"
                    logger -s -t "$SCRIPT_TAG" "Unmounted $_DEVICE from $_MOUNTPOINT"
                else
                    logger -s -t "$SCRIPT_TAG" "Failed to unmount $_DEVICE from $_MOUNTPOINT"
                fi
            fi
        ;;
    esac

    [ -n "$EXECUTE_COMMAND" ] && $EXECUTE_COMMAND "$1" "$_DEVICE"
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
                    logger -s -t "$SCRIPT_TAG" "Unknown hotplug action: $ACTION ($DEVICENAME)"
                    exit 1
                ;;
            esac
        fi
    ;;
    "start")
        cru a "$SCRIPT_NAME" "*/1 * * * * $SCRIPT_PATH run"

        for DEVICE in /dev/sd*; do
            [ -b "$DEVICE" ] && setup_mount add "$(basename "$DEVICENAME")"
        done
    ;;
    "stop")
        cru d "$SCRIPT_NAME"

        for DEVICE in /dev/sd*; do
            [ -b "$DEVICE" ] && setup_mount remove "$(basename "$DEVICENAME")"
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
