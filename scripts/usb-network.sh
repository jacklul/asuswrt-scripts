#!/bin/sh
# Made by Jack'lul <jacklul.github.io>
#
# Connect any USB networking gadget device to your LAN
#
# To be used with devices that can use USB Gadget mode.
# Raspberry Pi Zero will probably be the best for this.
# See https://github.com/jacklul/asuswrt-usb-raspberry-pi
#

#jas-update=usb-network.sh
#shellcheck disable=SC2155
#shellcheck source=./common.sh
readonly common_script="$(dirname "$0")/common.sh"
if [ -f "$common_script" ]; then . "$common_script"; else { echo "$common_script not found"; exit 1; } fi

BRIDGE_INTERFACE="br0" # bridge interface to add into, by default LAN bridge (br0) interface
EXECUTE_COMMAND="" # execute a command each time status changes (receives arguments: $1 = action (add/remove), $2 = interface)
RUN_EVERY_MINUTE= # scan for new interfaces to add to bridge periodically (true/false), empty means false when hotplug-event and service-event script are available but otherwise true

load_script_config

is_interface_up() {
    [ ! -d "/sys/class/net/$1" ] && return 1

    _operstate="$(cat "/sys/class/net/$1/operstate")"

    case "$_operstate" in
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
    [ -z "$BRIDGE_INTERFACE" ] && { logecho "Error: Bridge interface is not set"; exit 1; }
    [ -z "$2" ] && { echo "You must specify a network interface"; exit 1; }

    lockfile lockwait

    case "$1" in
        "add")
            [ ! -d "/sys/class/net/$2" ] && return

            if ! is_interface_up "$2"; then
                logecho "Bringing interface '$2' up..."
                ifconfig "$2" up
            fi

            if ! brctl show "$BRIDGE_INTERFACE" | grep -Fq "$2" && brctl addif "$BRIDGE_INTERFACE" "$2"; then
                logecho "Added interface '$2' to bridge '$BRIDGE_INTERFACE'" true
            fi
        ;;
        "remove")
            if brctl show "$BRIDGE_INTERFACE" | grep -Fq "$2" && brctl delif "$BRIDGE_INTERFACE" "$2"; then
                logecho "Removed interface '$2' from bridge '$BRIDGE_INTERFACE'" true
            fi

            if [ -d "/sys/class/net/$2" ] && is_interface_up "$2"; then
                logecho "Taking interface '$2' down..."
                ifconfig "$2" down
            fi
        ;;
    esac

    # no extra condition needed, already handled outside this function
    [ -n "$EXECUTE_COMMAND" ] && $EXECUTE_COMMAND "$1" "$2"

    lockfile unlock
}

setup_interfaces() {
    for interface in /sys/class/net/usb*; do
        [ -d "$interface" ] && setup_inteface "$1" "$(basename "$interface")"
    done
}

case "$1" in
    "run")
        bridge_members="$(brctl show "$BRIDGE_INTERFACE")"

        for interface in /sys/class/net/usb*; do
            [ ! -d "$interface" ] && continue

            interface="$(basename "$interface")"

            if ! echo "$bridge_members" | grep -Fq "$interface"; then
                setup_inteface add "$interface"
            fi
        done
    ;;
    "hotplug")
        if [ "$SUBSYSTEM" = "net" ] && [ "$(echo "$DEVICENAME" | cut -c 1-3)" = "usb" ]; then
            case "$ACTION" in
                "add")
                    setup_inteface add "$DEVICENAME"
                ;;
                "remove")
                    setup_inteface remove "$DEVICENAME"
                ;;
            esac
        fi
    ;;
    "start")
        setup_interfaces add

        # Set value of empty RUN_EVERY_MINUTE depending on situation
        execute_script_basename "service-event.sh" check && service_event_active=true
        execute_script_basename "hotplug-event.sh" check && hotplug_event_active=true
        [ -z "$RUN_EVERY_MINUTE" ] && { [ -z "$service_event_active" ] || [ -z "$hotplug_event_active" ] ; } && RUN_EVERY_MINUTE=true

        if [ "$RUN_EVERY_MINUTE" = true ]; then
            crontab_entry add "*/1 * * * * $script_path run"
        fi
    ;;
    "stop")
        crontab_entry delete
        setup_interfaces remove
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
