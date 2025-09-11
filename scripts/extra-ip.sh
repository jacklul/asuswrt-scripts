#!/bin/sh
# Made by Jack'lul <jacklul.github.io>
#
# Assign extra IPs to specified interfaces
#

#jas-update=extra-ip.sh
#shellcheck disable=SC2155
#shellcheck source=./common.sh
readonly common_script="$(dirname "$0")/common.sh"
if [ -f "$common_script" ]; then . "$common_script"; else { echo "$common_script not found"; exit 1; } fi

EXTRA_IPS="" # extra IP addresses to add, in format 'br0=192.168.1.254/24', separated by space
EXTRA_IPS6="" # same as EXTRA_IPS but for IPv6, in format 'br0=2001:db8::1/64', separated by space
RUN_EVERY_MINUTE= # verify that the addresses are still set (true/false), empty means false when service-event script is available but otherwise true

load_script_config

extra_ip() {
    { [ -z "$EXTRA_IPS" ] && [ -z "$EXTRA_IPS6" ] ; } && { logecho "Error: EXTRA_IPS/EXTRA_IPS6 is not set"; exit 1; }

    _for_ip="ip"
    [ "$(nvram get ipv6_service)" != "disabled" ] && _for_ip="$_for_ip ip6"

    for _ip in $_for_ip; do
        if [ "$_ip" = "ip6" ]; then
            _extra_ips="$EXTRA_IPS6"
            _ip="ip -6"
        else
            _extra_ips="$EXTRA_IPS"
            _ip="ip -4"
        fi

        [ -z "$_extra_ips" ] && continue

        for _extra_ip in $_extra_ips; do
            _interface=
            _label=
            _address=

            if echo "$_extra_ip" | grep -Fq "="; then
                _interface="$(echo "$_extra_ip" | cut -d '=' -f 1 2> /dev/null)"
                _address="$(echo "$_extra_ip" | cut -d '=' -f 2 2> /dev/null)"

                if echo "$_interface" | grep -Fq ":"; then
                    _label="$_interface"
                    _interface="$(echo "$_label" | cut -d ':' -f 1 2> /dev/null)"
                fi
            fi

            { [ -z "$_interface" ] || [ -z "$_address" ] ; } && { logecho "Invalid entry: $_extra_ip"; continue; }

            case "$1" in
                "add")
                    if ! $_ip addr show dev "$_interface" | grep -Fq " $_address "; then
                        if [ -n "$_label" ]; then
                            $_ip addr add "$_address" brd + dev "$_interface" label "$_label"
                        else
                            $_ip addr add "$_address" brd + dev "$_interface"
                        fi

                        logecho "Added address '$_address' to interface '$_interface'" true
                    fi
                ;;
                "remove")
                    if $_ip addr show dev "$_interface" | grep -Fq " $_address "; then
                        if [ -n "$_label" ]; then
                            $_ip addr delete "$_address" dev "$_interface" label "$_label"
                        else
                            $_ip addr delete "$_address" dev "$_interface"
                        fi

                        logecho "Removed address '$_address' from interface '$_interface'" true
                    fi
                ;;
            esac
        done
    done
}

case "$1" in
    "run")
        extra_ip add
    ;;
    "start")
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
