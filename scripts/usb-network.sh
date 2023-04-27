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

BRIDGE_INTERFACE="br0" # bridge interface to add into
EXECUTE_COMMAND="" # execute a command each time status changes, will pass arguments action (add or remove) and with interface name

readonly SCRIPT_NAME="$(basename "$0" .sh)"
readonly SCRIPT_PATH="$(readlink -f "$0")"
readonly SCRIPT_CONFIG="$(dirname "$0")/$SCRIPT_NAME.conf"
if [ -f "$SCRIPT_CONFIG" ]; then
    #shellcheck disable=SC1090
    . "$SCRIPT_CONFIG"
fi

hotplug_config() {
    case "$1" in
        "modify")
            if [ -f "/etc/hotplug2.rules" ]; then
                grep -q "$SCRIPT_PATH" /etc/hotplug2.rules && return # already modified

                LINE="$(grep -Fn "SUBSYSTEM == net, ACTION is set" /etc/hotplug2.rules)"

                if [ -n "$LINE" ]; then
                    cp "$(readlink -f /etc/hotplug2.rules)" /etc/hotplug2.rules.new

                    LINE="$(echo "$LINE" | cut -d":" -f1)"
                    LINE=$((LINE+2))
                    MD5="$(md5sum "/etc/hotplug2.rules.new")"

                    sed -i "$LINE i exec $SCRIPT_PATH hotplug ; " /etc/hotplug2.rules.new

                    if [ "$MD5" != "$(md5sum "/etc/hotplug2.rules.new")" ]; then
                        [ ! -f "/etc/hotplug2.rules.bak" ] && mv /etc/hotplug2.rules /etc/hotplug2.rules.bak
                        mv /etc/hotplug2.rules.new /etc/hotplug2.rules

                        killall hotplug2

                        logger -s -t "$SCRIPT_NAME" "Modified hotplug configuration"

                        return
                    fi
                fi
            fi
        ;;
        "restore")
            if [ -f "/etc/hotplug2.rules" ] && [ -f "/etc/hotplug2.rules.bak" ]; then
                cru d "$SCRIPT_NAME"

                rm /etc/hotplug2.rules
                mv /etc/hotplug2.rules.bak /etc/hotplug2.rules

                killall hotplug2

                logger -s -t "$SCRIPT_NAME" "Restored original hotplug configuration"
            fi
        ;;
    esac
}

setup_inteface() {
    _INTERFACE="$2"

    [ -z "$_INTERFACE" ] && { echo "You must specify a network interface"; exit 1; }
    [ -z "$BRIDGE_INTERFACE" ] && { echo "You must specify a bridge interface"; exit 1; }

    case "$1" in
        "add")
            [ ! -d "/sys/class/net/$_INTERFACE" ] && return

            is_interface_up "$_INTERFACE" || ifconfig "$_INTERFACE" up
            brctl show "$BRIDGE_INTERFACE" | grep -q "$_INTERFACE" || brctl addif "$BRIDGE_INTERFACE" "$_INTERFACE"

            logger -s -t "$SCRIPT_NAME" "Added interface $_INTERFACE to bridge $BRIDGE_INTERFACE"
        ;;
        "remove")
            brctl show "$BRIDGE_INTERFACE" | grep -q "$_INTERFACE" && brctl delif "$BRIDGE_INTERFACE" "$_INTERFACE"
            [ -d "/sys/class/net/$_INTERFACE" ] && is_interface_up "$_INTERFACE" && ifconfig "$_INTERFACE" down

            logger -s -t "$SCRIPT_NAME" "Removed interface $_INTERFACE from bridge $BRIDGE_INTERFACE"
        ;;
    esac

    [ -n "$EXECUTE_COMMAND" ] && $EXECUTE_COMMAND "$1" "$_INTERFACE"
}

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

case "$1" in
    "run")
        BRIDGE_MEMBERS="$(brctl show "$BRIDGE_INTERFACE")"

        for INTERFACE in /sys/class/net/usb*; do
            INTERFACE="$(basename "$INTERFACE")"

            if ! echo "$BRIDGE_MEMBERS" | grep -q "$INTERFACE"; then
                setup_inteface add "$INTERFACE"
            fi
        done
    ;;
    "hotplug")
        if [ "$(echo "$INTERFACE" | cut -c 1-3)" = "usb" ]; then
            case "$ACTION" in
                "add")
                    setup_inteface add "$INTERFACE"
                ;;
                "remove")
                    setup_inteface remove "$INTERFACE"
                ;;
                *)
                    logger -s -t "$SCRIPT_NAME" "Unknown hotplug action: $ACTION ($INTERFACE)"
                    exit 1
                ;;
            esac
        fi
    ;;
    "retry_until_success")
        sh "$SCRIPT_PATH" run

        brctl show "$BRIDGE_INTERFACE" | grep -q "usb" && cru l | grep "$SCRIPT_NAME" | grep -q "retry_until_success" && cru d "$SCRIPT_NAME"
    ;;
    "start")
        [ -z "$BRIDGE_INTERFACE" ] && { logger -s -t "$SCRIPT_NAME" "Unable to start - bridge interface is not set"; exit 1; }

        cru a "$SCRIPT_NAME" "*/1 * * * * $SCRIPT_PATH run"

        hotplug_config modify

        for INTERFACE in /sys/class/net/usb*; do
            setup_inteface add "$(basename "$INTERFACE")"
        done

        if ! brctl show "$BRIDGE_INTERFACE" | grep -q "usb" && ! cru l | grep -q "$SCRIPT_NAME"; then
            cru a "$SCRIPT_NAME" "*/1 * * * * $SCRIPT_PATH retry_until_success"

            logger -s -t "$SCRIPT_NAME" "Could not find any matching interface - will retry using crontab"
        fi
    ;;
    "stop")
        cru d "$SCRIPT_NAME"

        hotplug_config restore

        for INTERFACE in /sys/class/net/usb*; do
            setup_inteface remove "$(basename "$INTERFACE")"
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
