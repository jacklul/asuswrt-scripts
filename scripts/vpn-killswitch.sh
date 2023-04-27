#!/bin/sh
# Made by Jack'lul <jacklul.github.io>
#
# Prevent access to internet without VPN connection
#

#shellcheck disable=SC2155

BRIDGE_INTERFACE="br+" # the bridge interface to set rules for, by default affects all "br" interfaces

# These should not be changed
IPT="/usr/sbin/iptables"
IPT6="/usr/sbin/ip6tables"
CHAIN="VPN_KILLSWITCH"

readonly SCRIPT_NAME="$(basename "$0" .sh)"
readonly SCRIPT_PATH="$(readlink -f "$0")"
readonly SCRIPT_CONFIG="$(dirname "$0")/$SCRIPT_NAME.conf"
if [ -f "$SCRIPT_CONFIG" ]; then
    #shellcheck disable=SC1090
    . "$SCRIPT_CONFIG"
fi

FOR_IPTABLES="$IPT"

if [ "$(nvram get ipv6_service)" != "disabled" ]; then
    [ ! -f "$IPT6" ] && { echo "Missing ip6tables binary: $IPT6"; exit 1; }

    FOR_IPTABLES="$FOR_IPTABLES $IPT6"
fi

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

    for _IPTABLES in $FOR_IPTABLES; do
        case "$1" in
            "add")
                if ! $_IPTABLES -n -L "$CHAIN" >/dev/null 2>&1; then
                    $_IPTABLES -N "$CHAIN"
                    $_IPTABLES -I "$CHAIN" -j REJECT
                    $_IPTABLES -I FORWARD -i "$BRIDGE_INTERFACE" -o "$_WAN_INTERFACE" -j "$CHAIN"

                    logger -s -t "$SCRIPT_NAME" "Added firewall rules for VPN Kill-switch"
                fi
            ;;
            "remove")
                if $_IPTABLES -n -L "$CHAIN" >/dev/null 2>&1; then
                    $_IPTABLES -D FORWARD -i "$BRIDGE_INTERFACE" -o "$_WAN_INTERFACE" -j "$CHAIN"
                    $_IPTABLES -F "$CHAIN"
                    $_IPTABLES -X "$CHAIN"
                fi
            ;;
        esac
    done
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
