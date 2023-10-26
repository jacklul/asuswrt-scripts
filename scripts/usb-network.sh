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

                [ "$_LOCKWAITTIMER" -ge "$_LOCKWAITLIMIT" ] && { logger -s -t "$SCRIPT_TAG" "Unable to obtain lock after $_LOCKWAITLIMIT seconds, held by $_LOCKPID ($_LOCKCMD)"; exit 1; }
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
    _INTERFACE="$2"

    [ -z "$_INTERFACE" ] && { echo "You must specify a network interface"; exit 1; }
    [ -z "$BRIDGE_INTERFACE" ] && { echo "You must specify a bridge interface"; exit 1; }

    lockfile lock

    case "$1" in
        "add")
            [ ! -d "/sys/class/net/$_INTERFACE" ] && return

            is_interface_up "$_INTERFACE" || ifconfig "$_INTERFACE" up
            
            if ! brctl show "$BRIDGE_INTERFACE" | grep -q "$_INTERFACE"; then
                brctl addif "$BRIDGE_INTERFACE" "$_INTERFACE"

                logger -s -t "$SCRIPT_TAG" "Added interface $_INTERFACE to bridge $BRIDGE_INTERFACE"
            fi
        ;;
        "remove")
            if brctl show "$BRIDGE_INTERFACE" | grep -q "$_INTERFACE"; then
                brctl delif "$BRIDGE_INTERFACE" "$_INTERFACE"
                
                [ -d "/sys/class/net/$_INTERFACE" ] && is_interface_up "$_INTERFACE" && ifconfig "$_INTERFACE" down

                logger -s -t "$SCRIPT_TAG" "Removed interface $_INTERFACE from bridge $BRIDGE_INTERFACE"
            fi
        ;;
    esac

    [ -n "$EXECUTE_COMMAND" ] && $EXECUTE_COMMAND "$1" "$_INTERFACE"

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
                    logger -s -t "$SCRIPT_TAG" "Unknown hotplug action: $ACTION ($DEVICENAME)"
                    exit 1
                ;;
            esac
        fi
    ;;
    "start")
        [ -z "$BRIDGE_INTERFACE" ] && { logger -s -t "$SCRIPT_TAG" "Unable to start - bridge interface is not set"; exit 1; }

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
