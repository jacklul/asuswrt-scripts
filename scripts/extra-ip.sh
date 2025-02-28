#!/bin/sh
# Made by Jack'lul <jacklul.github.io>
#
# Assign extra IP to specified interface
#

#jacklul-asuswrt-scripts-update=extra-ip.sh
#shellcheck disable=SC2155,SC2009

readonly SCRIPT_PATH="$(readlink -f "$0")"
readonly SCRIPT_NAME="$(basename "$SCRIPT_PATH" .sh)"
readonly SCRIPT_DIR="$(dirname "$SCRIPT_PATH")"
readonly SCRIPT_CONFIG="$SCRIPT_DIR/$SCRIPT_NAME.conf"
readonly SCRIPT_TAG="$(basename "$SCRIPT_PATH")"

EXTRA_IPS="" # extra IP addresses to add, in format br0=192.168.1.254/24, multiple entries separated by space
EXTRA_IPS6="" # extra IPv6 addresses to add, in format br0=2001:db8::1/64, multiple entries separated by space
RUN_EVERY_MINUTE= # verify that the addresses are still set (true/false), empty means false when service-event.sh is available but otherwise true

if [ -f "$SCRIPT_CONFIG" ]; then
    #shellcheck disable=SC1090
    . "$SCRIPT_CONFIG"
fi

if [ -z "$RUN_EVERY_MINUTE" ]; then
    [ ! -x "$SCRIPT_DIR/service-event.sh" ] && RUN_EVERY_MINUTE=true
fi

# we did some changes, inform user of the change @TODO Remove it someday...
[ -n "$EXTRA_IP" ] && [ -z "$EXTRA_IPS" ] && echo "EXTRA_IP variable has been renamed into EXTRA_IPS and expects different format!"
[ -n "$EXTRA_IP6" ] && [ -z "$EXTRA_IPS6" ]  && echo "EXTRA_IP6 variable has been renamed into EXTRA_IPS6 and expects different format!"

extra_ip() {
    { [ -z "$EXTRA_IPS" ] && [ -z "$EXTRA_IPS6" ] ; } && { logger -st "$SCRIPT_TAG" "Extra IP addresses are not set"; exit 1; }

    for _EXTRA_IP in $EXTRA_IPS; do
        _INTERFACE=
        _ADDRESS=

        if echo "$_EXTRA_IP" | grep -q "="; then
            _ADDRESS="$(echo "$_EXTRA_IP" | cut -d '=' -f 2 2> /dev/null)"
            _INTERFACE="$(echo "$_EXTRA_IP" | cut -d '=' -f 1 2> /dev/null)"

            echo "$_ADDRESS" | grep -q "=" && { echo "Failed to parse list element: $_ADDRESS"; exit 1; } # no 'cut' command?
            { [ -z "$_INTERFACE" ] || [ -z "$_ADDRESS" ] ; } && { echo "List element is invalid: $_INTERFACE $_ADDRESS"; exit 1; }
        else
            echo "Variable EXTRA_IPS has invalid value"
            exit 1
        fi

        case "$1" in
            "add")
                if ! ip addr show dev "$_INTERFACE" | grep -q "inet $_ADDRESS "; then
                    ip -4 addr add "$_ADDRESS" dev "$_INTERFACE"
                    logger -st "$SCRIPT_TAG" "Added IPv4 address $_ADDRESS to interface $_INTERFACE"
                fi
            ;;
            "remove")
                if ip addr show dev "$_INTERFACE" | grep -q "inet $_ADDRESS "; then
                    ip -4 addr delete "$_ADDRESS" dev "$_INTERFACE"
                    logger -st "$SCRIPT_TAG" "Removed IPv4 address $_ADDRESS from interface $_INTERFACE"
                fi
            ;;
        esac
    done

    for _EXTRA_IP6 in $EXTRA_IPS6; do
        _INTERFACE=
        _ADDRESS=

        if echo "$_EXTRA_IP6" | grep -q "="; then
            _ADDRESS="$(echo "$_EXTRA_IP6" | cut -d '=' -f 2 2> /dev/null)"
            _INTERFACE="$(echo "$_EXTRA_IP6" | cut -d '=' -f 1 2> /dev/null)"

            echo "$_ADDRESS" | grep -q "=" && { echo "Failed to parse list element: $_ADDRESS"; exit 1; } # no 'cut' command?
            { [ -z "$_INTERFACE" ] || [ -z "$_ADDRESS" ] ; } && { echo "List element is invalid: $_INTERFACE $_ADDRESS"; exit 1; }
        else
            echo "Variable EXTRA_IPS6 has invalid value"
            exit 1
        fi

        case "$1" in
            "add")
                if [ -n "$_ADDRESS" ] && ! ip addr show dev "$_INTERFACE" | grep -q "inet6 $_ADDRESS "; then
                    ip -6 addr add "$_ADDRESS" dev "$_INTERFACE"
                    logger -st "$SCRIPT_TAG" "Added IPv6 address $_ADDRESS to interface $_INTERFACE"
                fi
            ;;
            "remove")
                if [ -n "$_ADDRESS" ] && ip addr show dev "$_INTERFACE" | grep -q "inet6 $_ADDRESS "; then
                    ip -6 addr delete "$_ADDRESS" dev "$_INTERFACE"
                    logger -st "$SCRIPT_TAG" "Removed IPv6 address $_ADDRESS from interface $_INTERFACE"
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
        { [ -z "$EXTRA_IPS" ] && [ -z "$EXTRA_IPS6" ] ; } && { logger -st "$SCRIPT_TAG" "Extra IP(s) are not set"; exit 1; }

        if [ "$RUN_EVERY_MINUTE" = true ]; then
            if [ -x "$SCRIPT_DIR/cron-queue.sh" ]; then
                sh "$SCRIPT_DIR/cron-queue.sh" add "$SCRIPT_NAME" "$SCRIPT_PATH run"
            else
                cru a "$SCRIPT_NAME" "*/1 * * * * $SCRIPT_PATH run"
            fi
        fi

        extra_ip add
    ;;
    "stop")
        [ -x "$SCRIPT_DIR/cron-queue.sh" ] && sh "$SCRIPT_DIR/cron-queue.sh" remove "$SCRIPT_NAME"
        cru d "$SCRIPT_NAME"

        extra_ip remove
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
