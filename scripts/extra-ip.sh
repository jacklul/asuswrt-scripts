#!/bin/sh
# Made by Jack'lul <jacklul.github.io>
#
# Assign extra IP to specified interface
#

#jacklul-asuswrt-scripts-update=extra-ip.sh
#shellcheck disable=SC2155,SC2009

readonly script_path="$(readlink -f "$0")"
readonly script_name="$(basename "$script_path" .sh)"
readonly script_dir="$(dirname "$script_path")"
readonly script_config="$script_dir/$script_name.conf"

EXTRA_IPS="" # extra IP addresses to add, in format br0=192.168.1.254/24, multiple entries separated by space
EXTRA_IPS6="" # extra IPv6 addresses to add, in format br0=2001:db8::1/64, multiple entries separated by space
RUN_EVERY_MINUTE= # verify that the addresses are still set (true/false), empty means false when service-event.sh is available but otherwise true

if [ -f "$script_config" ]; then
    #shellcheck disable=SC1090
    . "$script_config"
fi

if [ -z "$RUN_EVERY_MINUTE" ]; then
    [ ! -x "$script_dir/service-event.sh" ] && RUN_EVERY_MINUTE=true
fi

# we did some changes, inform user of the change @TODO Remove it someday...
[ -n "$EXTRA_IP" ] && [ -z "$EXTRA_IPS" ] && echo "EXTRA_IP variable has been renamed into EXTRA_IPS and expects different format!"
[ -n "$EXTRA_IP6" ] && [ -z "$EXTRA_IPS6" ]  && echo "EXTRA_IP6 variable has been renamed into EXTRA_IPS6 and expects different format!"

extra_ip() {
    { [ -z "$EXTRA_IPS" ] && [ -z "$EXTRA_IPS6" ] ; } && { logger -st "$script_name" "Extra IP addresses are not set"; exit 1; }

    for _extra_ip in $EXTRA_IPS; do
        _interface=
        _address=

        if echo "$_extra_ip" | grep -q "="; then
            _address="$(echo "$_extra_ip" | cut -d '=' -f 2 2> /dev/null)"
            _interface="$(echo "$_extra_ip" | cut -d '=' -f 1 2> /dev/null)"

            echo "$_address" | grep -q "=" && { echo "Failed to parse list element: $_address"; exit 1; } # no 'cut' command?
            { [ -z "$_interface" ] || [ -z "$_address" ] ; } && { echo "List element is invalid: $_interface $_address"; exit 1; }
        else
            echo "Variable EXTRA_IPS has invalid value"
            exit 1
        fi

        case "$1" in
            "add")
                if ! ip addr show dev "$_interface" | grep -q "inet $_address "; then
                    ip -4 addr add "$_address" brd + dev "$_interface"
                    logger -st "$script_name" "Added IPv4 address $_address to interface $_interface"
                fi
            ;;
            "remove")
                if ip addr show dev "$_interface" | grep -q "inet $_address "; then
                    ip -4 addr delete "$_address" dev "$_interface"
                    logger -st "$script_name" "Removed IPv4 address $_address from interface $_interface"
                fi
            ;;
        esac
    done

    for _extra_ip6 in $EXTRA_IPS6; do
        _interface=
        _address=

        if echo "$_extra_ip6" | grep -q "="; then
            _address="$(echo "$_extra_ip6" | cut -d '=' -f 2 2> /dev/null)"
            _interface="$(echo "$_extra_ip6" | cut -d '=' -f 1 2> /dev/null)"

            echo "$_address" | grep -q "=" && { echo "Failed to parse list element: $_address"; exit 1; } # no 'cut' command?
            { [ -z "$_interface" ] || [ -z "$_address" ] ; } && { echo "List element is invalid: $_interface $_address"; exit 1; }
        else
            echo "Variable EXTRA_IPS6 has invalid value"
            exit 1
        fi

        case "$1" in
            "add")
                if [ -n "$_address" ] && ! ip addr show dev "$_interface" | grep -q "inet6 $_address "; then
                    ip -6 addr add "$_address" brd + dev "$_interface"
                    logger -st "$script_name" "Added IPv6 address $_address to interface $_interface"
                fi
            ;;
            "remove")
                if [ -n "$_address" ] && ip addr show dev "$_interface" | grep -q "inet6 $_address "; then
                    ip -6 addr delete "$_address" dev "$_interface"
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
        { [ -z "$EXTRA_IPS" ] && [ -z "$EXTRA_IPS6" ] ; } && { logger -st "$script_name" "Extra IP(s) are not set"; exit 1; }

        if [ "$RUN_EVERY_MINUTE" = true ]; then
            if [ -x "$script_dir/cron-queue.sh" ]; then
                sh "$script_dir/cron-queue.sh" add "$script_name" "$script_path run"
            else
                cru a "$script_name" "*/1 * * * * $script_path run"
            fi
        fi

        extra_ip add
    ;;
    "stop")
        [ -x "$script_dir/cron-queue.sh" ] && sh "$script_dir/cron-queue.sh" remove "$script_name"
        cru d "$script_name"

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
