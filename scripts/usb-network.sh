#!/bin/sh
# Made by Jack'lul <jacklul.github.io>
#
# Connects any USB networking device to your LAN
#
# To be used with devices that can use USB Gadget mode.
# Raspberry Pi Zero will probably be the best for this.
# See https://github.com/jacklul/asuswrt-usb-raspberry-pi
#

#shellcheck disable=SC2155

readonly SCRIPT_PATH="$(readlink -f "$0")"
readonly SCRIPT_NAME="$(basename "$SCRIPT_PATH" .sh)"
readonly SCRIPT_DIR="$(dirname "$SCRIPT_PATH")"
readonly SCRIPT_CONFIG="$SCRIPT_DIR/$SCRIPT_NAME.conf"
readonly SCRIPT_TAG="$(basename "$SCRIPT_PATH")"

BRIDGE_INTERFACE="br0" # bridge interface to add into, by default LAN bridge ("br0") interface
EXECUTE_COMMAND="" # execute a command each time status changes (receives arguments: $1 = action, $2 = interface)

if [ -f "$SCRIPT_CONFIG" ]; then
    #shellcheck disable=SC1090
    . "$SCRIPT_CONFIG"
fi

lockfile() { #LOCKFUNC_START#
    _LOCKFILE="/var/lock/script-$SCRIPT_NAME.lock"
    _FD=9

    case "$1" in
        "lock")
            eval exec "$_FD>$_LOCKFILE"
            flock -x $_FD
            trap 'flock -u $_FD; rm -f "$_LOCKFILE"; exit $?' EXIT
        ;;
        "unlock")
            flock -u "$_FD"
            rm -f "$_LOCKFILE"
            trap - EXIT
        ;;
    esac
} #LOCKFUNC_END#

is_interface_up() {
    [ ! -d "/sys/class/net/$1" ] && return 1

    _OPERSTATE="$(cat "/sys/class/net/$1/operstate")"

    case "$_OPERSTATE" in
        "up")
            return 0
        ;;
        "unknown")
            [ "$(cat "/sys/class/net/$1/carrier")" = "1" ] && return 0
        ;;
    esac

    # All other states: down, notpresent, lowerlayerdown, testing, dormant
    return 1
}

setup_inteface() {
    [ -z "$BRIDGE_INTERFACE" ] && { logger -st "$SCRIPT_TAG" "Bridge interface is not set"; exit 1; }
    [ -z "$2" ] && { echo "You must specify a network interface"; exit 1; }

    lockfile lock

    case "$1" in
        "add")
            [ ! -d "/sys/class/net/$2" ] && return

            if ! is_interface_up "$2"; then
                logger -st "$SCRIPT_TAG" "Bringing interface $2 up..."
                ifconfig "$2" up
            fi

            if ! brctl show "$BRIDGE_INTERFACE" | grep -q "$2" && brctl addif "$BRIDGE_INTERFACE" "$2"; then
                logger -st "$SCRIPT_TAG" "Added interface $2 to bridge $BRIDGE_INTERFACE"
            fi
        ;;
        "remove")
            if brctl show "$BRIDGE_INTERFACE" | grep -q "$2" && brctl delif "$BRIDGE_INTERFACE" "$2"; then
                logger -st "$SCRIPT_TAG" "Removed interface $2 from bridge $BRIDGE_INTERFACE"
            fi

            if [ -d "/sys/class/net/$2" ] && is_interface_up "$2"; then
                logger -st "$SCRIPT_TAG" "Taking interface $2 down..."
                ifconfig "$2" down
            fi
        ;;
    esac

    [ -n "$EXECUTE_COMMAND" ] && $EXECUTE_COMMAND "$1" "$2"

    lockfile unlock
}

case "$1" in
    "run")
        BRIDGE_MEMBERS="$(brctl show "$BRIDGE_INTERFACE")"

        for INTERFACE in /sys/class/net/usb*; do
            [ ! -d "$INTERFACE" ] && continue

            INTERFACE="$(basename "$INTERFACE")"

            if ! echo "$BRIDGE_MEMBERS" | grep -q "$INTERFACE"; then
                setup_inteface add "$INTERFACE"
            fi
        done
    ;;
    "hotplug")
        if [ "$(echo "$DEVICENAME" | cut -c 1-3)" = "usb" ]; then
            case "$ACTION" in
                "add")
                    setup_inteface add "$DEVICENAME"
                ;;
                "remove")
                    setup_inteface remove "$DEVICENAME"
                ;;
                *)
                    logger -st "$SCRIPT_TAG" "Unknown hotplug action: $ACTION ($DEVICENAME)"
                    exit 1
                ;;
            esac
        fi
    ;;
    "start")
        [ -z "$BRIDGE_INTERFACE" ] && { logger -st "$SCRIPT_TAG" "Unable to start - bridge interface is not set"; exit 1; }

        cru a "$SCRIPT_NAME" "*/1 * * * * $SCRIPT_PATH run"

        for INTERFACE in /sys/class/net/usb*; do
            [ -d "$INTERFACE" ] && setup_inteface add "$(basename "$INTERFACE")"
        done
    ;;
    "stop")
        cru d "$SCRIPT_NAME"

        for INTERFACE in /sys/class/net/usb*; do
            [ -d "$INTERFACE" ] && setup_inteface remove "$(basename "$INTERFACE")"
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
