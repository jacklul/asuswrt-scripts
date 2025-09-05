#!/bin/sh
# Made by Jack'lul <jacklul.github.io>
#
# Assign extra IP to specified interface
#

#jas-update=extra-ip.sh
#shellcheck disable=SC2155
#shellcheck source=./common.sh
readonly common_script="$(dirname "$0")/common.sh"
if [ -f "$common_script" ]; then . "$common_script"; else { echo "$common_script not found"; exit 1; } fi

EXTRA_IPS="" # extra IP addresses to add, in format br0=192.168.1.254/24, multiple entries separated by space
EXTRA_IPS6="" # extra IPv6 addresses to add, in format br0=2001:db8::1/64, multiple entries separated by space
RUN_EVERY_MINUTE= # verify that the addresses are still set (true/false), empty means false when service-event script is available but otherwise true

load_script_config

extra_ip() {
    { [ -z "$EXTRA_IPS" ] && [ -z "$EXTRA_IPS6" ] ; } && { logger -st "$script_name" "Error: Extra IP addresses are not set"; exit 1; }

    for _extra_ip in $EXTRA_IPS; do
        _interface=
        _label=
        _address=

        if echo "$_extra_ip" | grep -Fq "="; then
            _address="$(echo "$_extra_ip" | cut -d '=' -f 2 2> /dev/null)"
            _interface="$(echo "$_extra_ip" | cut -d '=' -f 1 2> /dev/null)"

            if echo "$_interface" | grep -Fq ":"; then
                _label="$_interface"
                _interface="$(echo "$_label" | cut -d ':' -f 1 2> /dev/null)"
            fi

            echo "$_address" | grep -Fq "=" && { echo "Failed to parse list element: $_address"; exit 1; } # no 'cut' command?
            { [ -z "$_interface" ] || [ -z "$_address" ] ; } && { echo "List element is invalid: $_interface $_address"; exit 1; }
        else
            logger -st "$script_name" "Variable EXTRA_IPS has invalid value"
            exit 1
        fi

        case "$1" in
            "add")
                if ! ip addr show dev "$_interface" | grep -Fq "inet $_address"; then
                    if [ -n "$_label" ]; then
                        ip -4 addr add "$_address" brd + dev "$_interface" label "$_label"
                    else
                        ip -4 addr add "$_address" brd + dev "$_interface"
                    fi

                    logger -st "$script_name" "Added IPv4 address $_address to interface $_interface"
                fi
            ;;
            "remove")
                if ip addr show dev "$_interface" | grep -Fq "inet $_address"; then
                    if [ -n "$_label" ]; then
                        ip -4 addr delete "$_address" dev "$_interface" label "$_label"
                    else
                        ip -4 addr delete "$_address" dev "$_interface"
                    fi

                    logger -st "$script_name" "Removed IPv4 address $_address from interface $_interface"
                fi
            ;;
        esac
    done

    for _extra_ip6 in $EXTRA_IPS6; do
        _interface=
        _label=
        _address=

        if echo "$_extra_ip6" | grep -Fq "="; then
            _address="$(echo "$_extra_ip6" | cut -d '=' -f 2 2> /dev/null)"
            _interface="$(echo "$_extra_ip6" | cut -d '=' -f 1 2> /dev/null)"

            if echo "$_interface" | grep -Fq ":"; then
                _label="$_interface"
                _interface="$(echo "$_label" | cut -d ':' -f 1 2> /dev/null)"
            fi

            echo "$_address" | grep -Fq "=" && { echo "Failed to parse list element: $_address"; exit 1; } # no 'cut' command?
            { [ -z "$_interface" ] || [ -z "$_address" ] ; } && { echo "List element is invalid: $_interface $_address"; exit 1; }
        else
            logger -st "$script_name" "Variable EXTRA_IPS6 has invalid value"
            exit 1
        fi

        case "$1" in
            "add")
                if [ -n "$_address" ] && ! ip addr show dev "$_interface" | grep -Fq "inet6 $_address"; then
                    if [ -n "$_label" ]; then
                        ip -6 addr add "$_address" brd + dev "$_interface" label "$_label"
                    else
                        ip -6 addr add "$_address" brd + dev "$_interface"
                    fi

                    logger -st "$script_name" "Added IPv6 address $_address to interface $_interface"
                fi
            ;;
            "remove")
                if [ -n "$_address" ] && ip addr show dev "$_interface" | grep -Fq "inet6 $_address"; then
                    if [ -n "$_label" ]; then
                        ip -6 addr delete "$_address" dev "$_interface" label "$_label"
                    else
                        ip -6 addr delete "$_address" dev "$_interface"
                    fi

                    logger -st "$script_name" "Removed IPv6 address $_address from interface $_interface"
                fi
            ;;
        esac
    done
}

case "$1" in
    "run")
        extra_ip add
    ;;
    "start")
        { [ -z "$EXTRA_IPS" ] && [ -z "$EXTRA_IPS6" ] ; } && { logger -st "$script_name" "Unable to start - extra IP(s) are not set"; exit 1; }

        extra_ip add

        # Set value of empty RUN_EVERY_MINUTE depending on situation
        execute_script_basename "service-event.sh" check && service_event_active=true
        [ -z "$RUN_EVERY_MINUTE" ] && [ -z "$service_event_active" ] && RUN_EVERY_MINUTE=true

        if [ "$RUN_EVERY_MINUTE" = true ]; then
            crontab_entry add "*/1 * * * * $script_path run"
        fi
    ;;
    "stop")
        crontab_entry delete
        extra_ip remove
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
