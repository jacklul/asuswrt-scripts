#!/bin/sh
# Made by Jack'lul <jacklul.github.io>
#
# Enables VPN clients to access Samba shares in LAN
#

#shellcheck disable=SC2155

readonly SCRIPT_PATH="$(readlink -f "$0")"
readonly SCRIPT_NAME="$(basename "$SCRIPT_PATH" .sh)"
readonly SCRIPT_DIR="$(dirname "$SCRIPT_PATH")"
readonly SCRIPT_CONFIG="$SCRIPT_DIR/$SCRIPT_NAME.conf"
readonly SCRIPT_TAG="$(basename "$SCRIPT_PATH")"

VPN_NETWORKS="10.6.0.0/24 10.8.0.0/24 10.10.10.0/24" # VPN networks (IPv4) to allow access to Samba from, separated by spaces
VPN_NETWORKS6="" # VPN networks (IPv6) to allow access to Samba from, separated by spaces
BRIDGE_INTERFACE="br0" # the bridge interface to set rules for, by default only LAN bridge ("br0") interface

if [ -f "$SCRIPT_CONFIG" ]; then
    #shellcheck disable=SC1090
    . "$SCRIPT_CONFIG"
fi

CHAIN="SAMBA_MASQUERADE"
FOR_IPTABLES="iptables"

[ "$(nvram get ipv6_service)" != "disabled" ] && FOR_IPTABLES="$FOR_IPTABLES ip6tables"

firewall_rules() {
    [ -z "$BRIDGE_INTERFACE" ] && { logger -s -t "$SCRIPT_TAG" "Bridge interface is not set"; exit 1; }
    [ -z "$VPN_NETWORKS" ] && { logger -s -t "Allowed VPN networks are not set"; exit 1; }

    for _IPTABLES in $FOR_IPTABLES; do
        if [ "$_IPTABLES" = "ip6tables" ]; then
            _VPN_NETWORKS="$VPN_NETWORKS6"
        else
            _VPN_NETWORKS="$VPN_NETWORKS"
        fi

        [ -z "$_VPN_NETWORKS" ] && continue

        case "$1" in
            "add")
                if ! $_IPTABLES -n -L "$CHAIN" >/dev/null 2>&1; then
                    $_IPTABLES -N "$CHAIN"
                    $_IPTABLES -A "$CHAIN" -t nat -p tcp --dport 445 -j MASQUERADE
                    $_IPTABLES -A "$CHAIN" -t nat -p tcp --dport 139 -j MASQUERADE
                    $_IPTABLES -A "$CHAIN" -t nat -p udp --dport 138 -j MASQUERADE
                    $_IPTABLES -A "$CHAIN" -t nat -p udp --dport 137 -j MASQUERADE
                    $_IPTABLES -A "$CHAIN" -t nat -p icmp --icmp-type 1 -j MASQUERADE
                    $_IPTABLES -A "$CHAIN" -t nat -j RETURN

                    for _VPN_NETWORK in $_VPN_NETWORKS; do
                        $_IPTABLES -A "POSTROUTING -t nat -s $_VPN_NETWORK -o $BRIDGE_INTERFACE -j SAMBA_MASQUERADE"
                    done
                fi
            ;;
            "remove")
                if $_IPTABLES -n -L "$CHAIN" >/dev/null 2>&1; then
                    for _VPN_NETWORK in $_VPN_NETWORKS; do
                        $_IPTABLES -D "POSTROUTING -t nat -s $_VPN_NETWORK -o $BRIDGE_INTERFACE -j SAMBA_MASQUERADE"
                    done

                    $_IPTABLES -F "$CHAIN"
                    $_IPTABLES -X "$CHAIN"
                fi
            ;;
        esac
    done

    [ "$1" = "add" ] && logger -s -t "$SCRIPT_TAG" "Added firewall rules for Samba Masquerade (VPNs: $(echo "$VPN_NETWORKS $VPN_NETWORKS6" | awk '{$1=$1};1'))"
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
