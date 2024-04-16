#!/bin/sh
# Made by Jack'lul <jacklul.github.io>
#
# Connects any USB networking device to your LAN
#
# To be used with devices that can use USB Gadget mode.
# Raspberry Pi Zero will probably be the best for this.
# See https://github.com/jacklul/asuswrt-usb-raspberry-pi
#

# jacklul-asuswrt-scripts-update
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
                echo "File descriptor $_FD is already in use ($(readlink -f "/proc/$$/fd/$_FD"))"
                _FD=$((_FD+1))

                [ "$_FD" -gt "$_FD_MAX" ] && exit 1
            done

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

    lockfile lockwait

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

        if [ -x "$SCRIPT_DIR/cron-queue.sh" ]; then
            sh "$SCRIPT_DIR/cron-queue.sh" add "$SCRIPT_NAME" "$SCRIPT_PATH run"
        else
            cru a "$SCRIPT_NAME" "*/1 * * * * $SCRIPT_PATH run"
        fi

        for INTERFACE in /sys/class/net/usb*; do
            [ -d "$INTERFACE" ] && setup_inteface add "$(basename "$INTERFACE")"
        done
    ;;
    "stop")
        [ -x "$SCRIPT_DIR/cron-queue.sh" ] && sh "$SCRIPT_DIR/cron-queue.sh" remove "$SCRIPT_NAME"
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
