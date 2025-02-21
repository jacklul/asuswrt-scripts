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

TARGET_INTERFACE="br0"
EXTRA_IP="" # IP address to add to the interface, in format 192.168.1.254/24
EXTRA_IP6="" # IPv6 address to add to the interface, in format 2001:db8::1/64

if [ -f "$SCRIPT_CONFIG" ]; then
    #shellcheck disable=SC1090
    . "$SCRIPT_CONFIG"
fi

extra_ip() {
    [ -z "$TARGET_INTERFACE" ] && { logger -st "$SCRIPT_TAG" "Target interface is not set"; exit 1; }

    case "$1" in
        "add")
            if [ -n "$EXTRA_IP" ] && ! ip addr show dev "$TARGET_INTERFACE" | grep -q "inet $EXTRA_IP "; then
                ip -4 addr add "$EXTRA_IP" dev "$TARGET_INTERFACE"
                logger -st "$SCRIPT_TAG" "Added IPv4 address $EXTRA_IP to interface $TARGET_INTERFACE"
            fi

            if [ -n "$EXTRA_IP6" ] && ! ip addr show dev "$TARGET_INTERFACE" | grep -q "inet6 $EXTRA_IP6 "; then
                ip -6 addr add "$EXTRA_IP6" dev "$TARGET_INTERFACE"
                logger -st "$SCRIPT_TAG" "Added IPv6 address $EXTRA_IP6 to interface $TARGET_INTERFACE"
            fi
        ;;
        "remove")
            if [ -n "$EXTRA_IP" ] && ip addr show dev "$TARGET_INTERFACE" | grep -q "inet $EXTRA_IP "; then
                ip -4 addr delete "$EXTRA_IP" dev "$TARGET_INTERFACE"
                logger -st "$SCRIPT_TAG" "Removed IPv4 address $EXTRA_IP from interface $TARGET_INTERFACE"
            fi

            if [ -n "$EXTRA_IP6" ] && ip addr show dev "$TARGET_INTERFACE" | grep -q "inet6 $EXTRA_IP6 "; then
                ip -6 addr delete "$EXTRA_IP6" dev "$TARGET_INTERFACE"
                logger -st "$SCRIPT_TAG" "Removed IPv6 address $EXTRA_IP6 from interface $TARGET_INTERFACE"
            fi
        ;;
    esac
}

case "$1" in
    "run")
        extra_ip add
    ;;
    "start")
        { [ -z "$EXTRA_IP" ] && [ -z "$EXTRA_IP6" ]; } && { logger -st "$SCRIPT_TAG" "Extra IP(s) are not set"; exit 1; }

        if [ -x "$SCRIPT_DIR/cron-queue.sh" ]; then
            sh "$SCRIPT_DIR/cron-queue.sh" add "$SCRIPT_NAME" "$SCRIPT_PATH run"
        else
            cru a "$SCRIPT_NAME" "*/1 * * * * $SCRIPT_PATH run"
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
