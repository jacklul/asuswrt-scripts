#!/bin/sh
# Made by Jack'lul <jacklul.github.io>
#
# Prevent access to internet without VPN connection
#
# Based on:
#  https://github.com/ZebMcKayhan/WireguardManager/blob/main/wg_manager.sh
#

#shellcheck disable=SC2155

readonly SCRIPT_PATH="$(readlink -f "$0")"
readonly SCRIPT_NAME="$(basename "$SCRIPT_PATH" .sh)"
readonly SCRIPT_DIR="$(dirname "$SCRIPT_PATH")"
readonly SCRIPT_CONFIG="$SCRIPT_DIR/$SCRIPT_NAME.conf"
readonly SCRIPT_TAG="$(basename "$SCRIPT_PATH")"

BRIDGE_INTERFACE="br+" # the bridge interface to set rules for, by default affects all "br" interfaces (which also includes guest network bridge)

if [ -f "$SCRIPT_CONFIG" ]; then
    #shellcheck disable=SC1090
    . "$SCRIPT_CONFIG"
fi

CHAIN="VPN_KILLSWITCH"
FOR_IPTABLES="iptables"

[ "$(nvram get ipv6_service)" != "disabled" ] && FOR_IPTABLES="$FOR_IPTABLES ip6tables"

get_wan_interface() {
    _INTERFACE="$(nvram get wan0_ifname)"

    if [ "$(nvram get wan0_gw_ifname)" != "$_INTERFACE" ];then
        _INTERFACE=$(nvram get wan0_gw_ifname)
    fi

    if [ -n "$(nvram get wan0_pppoe_ifname)" ]; then
        _INTERFACE="$(nvram get wan0_pppoe_ifname)"
    fi

    echo "$_INTERFACE"
}

firewall_rules() {
    _WAN_INTERFACE="$(get_wan_interface)"

    [ -z "$BRIDGE_INTERFACE" ] && { logger -s -t "$SCRIPT_TAG" "Bridge interface is not set"; exit 1; }
    [ -z "$_WAN_INTERFACE" ] && { logger -s -t "$SCRIPT_TAG" "Couldn't get WAN interface name"; exit 1; }

    for _IPTABLES in $FOR_IPTABLES; do
        case "$1" in
            "add")
                if ! $_IPTABLES -nL "$CHAIN" >/dev/null 2>&1; then
                    $_IPTABLES -N "$CHAIN"
                    $_IPTABLES -I "$CHAIN" -j REJECT
                    $_IPTABLES -I FORWARD -i "$BRIDGE_INTERFACE" -o "$_WAN_INTERFACE" -j "$CHAIN"
                fi
            ;;
            "remove")
                if $_IPTABLES -nL "$CHAIN" >/dev/null 2>&1; then
                    $_IPTABLES -D FORWARD -i "$BRIDGE_INTERFACE" -o "$_WAN_INTERFACE" -j "$CHAIN"
                    $_IPTABLES -F "$CHAIN"
                    $_IPTABLES -X "$CHAIN"
                fi
            ;;
        esac
    done

    [ "$1" = "add" ] && logger -s -t "$SCRIPT_TAG" "Added firewall rules for VPN Kill-switch"
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
