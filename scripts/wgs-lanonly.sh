#!/bin/sh
# Made by Jack'lul <jacklul.github.io>
#
# Prevent WireGuard server clients from accessing internet through the router
#

#shellcheck disable=SC2155

readonly SCRIPT_PATH="$(readlink -f "$0")"
readonly SCRIPT_NAME="$(basename "$SCRIPT_PATH" .sh)"
readonly SCRIPT_DIR="$(dirname "$SCRIPT_PATH")"
readonly SCRIPT_CONFIG="$SCRIPT_DIR/$SCRIPT_NAME.conf"
readonly SCRIPT_TAG="$(basename "$SCRIPT_PATH")"

INTERFACE="wgs1" # WireGuard server interface (find it through 'nvram show | grep wgs' or 'ifconfig' command)
BRIDGE_INTERFACE="br0" # the bridge interface(s) to limit access to, by default only LAN bridge ("br0") interface
EXECUTE_COMMAND="" # execute a command after firewall rules are applied or removed (receives arguments: $1 = action)

if [ -f "$SCRIPT_CONFIG" ]; then
    #shellcheck disable=SC1090
    . "$SCRIPT_CONFIG"
fi

CHAIN="WGS_LANONLY"
FOR_IPTABLES="iptables"

[ "$(nvram get ipv6_service)" != "disabled" ] && FOR_IPTABLES="$FOR_IPTABLES ip6tables"

firewall_rules() {
    [ -z "$INTERFACE" ] && { logger -s -t "$SCRIPT_TAG" "Target interface is not set"; exit 1; }
    [ -z "$BRIDGE_INTERFACE" ] && { logger -s -t "$SCRIPT_TAG" "Bridge interface is not set"; exit 1; }

    _RULES_ADDED=0

    for _IPTABLES in $FOR_IPTABLES; do
        case "$1" in
            "add")
                if ! $_IPTABLES -nL "$CHAIN" >/dev/null 2>&1; then
                    _RULES_ADDED=1

                    _FORWARD_START="$($_IPTABLES -nL FORWARD --line-numbers | grep -E "all.*state RELATED,ESTABLISHED" | tail -1 | awk '{print $1}')"
                    _FORWARD_START_PLUS="$((_FORWARD_START+1))"

                    $_IPTABLES -N "$CHAIN"
                    $_IPTABLES -A "$CHAIN" ! -o "$BRIDGE_INTERFACE" -j DROP
                    $_IPTABLES -A "$CHAIN" -j RETURN

                    $_IPTABLES -I FORWARD "$_FORWARD_START_PLUS" -i "$INTERFACE" -j "$CHAIN"
                fi
            ;;
            "remove")
                if $_IPTABLES -nL "$CHAIN" >/dev/null 2>&1; then
                    $_IPTABLES -D FORWARD -i "$INTERFACE" -j "$CHAIN"

                    $_IPTABLES -F "$CHAIN"
                    $_IPTABLES -X "$CHAIN"
                fi
            ;;
        esac
    done

    [ "$_RULES_ADDED" = 1 ] && logger -s -t "$SCRIPT_TAG" "Added firewall rules for WireGuard Server LAN-only mode"

    [ -n "$EXECUTE_COMMAND" ] && $EXECUTE_COMMAND "$1"
}

case "$1" in
    "run")
        firewall_rules add
    ;;
    "start")
        cru a "$SCRIPT_NAME" "*/1 * * * * $SCRIPT_PATH run"

        firewall_rules add
    ;;
    "stop")
        cru d "$SCRIPT_NAME"

        firewall_rules remove
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
