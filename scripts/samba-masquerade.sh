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
EXECUTE_COMMAND="" # execute a command after firewall rules are applied or removed (receives arguments: $1 = action)

if [ -f "$SCRIPT_CONFIG" ]; then
    #shellcheck disable=SC1090
    . "$SCRIPT_CONFIG"
fi

CHAIN="SAMBA_MASQUERADE"
FOR_IPTABLES="iptables"

[ "$(nvram get ipv6_service)" != "disabled" ] && FOR_IPTABLES="$FOR_IPTABLES ip6tables"

lockfile() { #LOCKFUNC_START#
    _LOCKFILE="/var/lock/script-$SCRIPT_NAME.lock"
    _FD=9

    case "$1" in
        "lock")
            eval exec "$_FD>$_LOCKFILE"
            flock -x $_FD
            trap 'flock -u $_FD; rm -f "$_LOCKFILE"; exit $?' EXIT
        ;;
        "unlock")
            flock -u "$_FD"
            rm -f "$_LOCKFILE"
            trap - EXIT
        ;;
    esac
} #LOCKFUNC_END#

firewall_rules() {
    [ -z "$BRIDGE_INTERFACE" ] && { logger -st "$SCRIPT_TAG" "Bridge interface is not set"; exit 1; }
    [ -z "$VPN_NETWORKS" ] && { logger -st "$SCRIPT_TAG" "Allowed VPN networks are not set"; exit 1; }

    lockfile lock

    _RULES_ADDED=0
    for _IPTABLES in $FOR_IPTABLES; do
        if [ "$_IPTABLES" = "ip6tables" ]; then
            _VPN_NETWORKS="$VPN_NETWORKS6"
        else
            _VPN_NETWORKS="$VPN_NETWORKS"
        fi

        [ -z "$_VPN_NETWORKS" ] && continue

        _DESTINATION_NETWORK="$($_IPTABLES -t nat -nvL POSTROUTING --line-numbers | grep -E " MASQUERADE .*$BRIDGE_INTERFACE" | head -1 | awk '{print $9}')"

        case "$1" in
            "add")
                if ! $_IPTABLES -t nat -nL "$CHAIN" >/dev/null 2>&1; then
                    _RULES_ADDED=1

                    $_IPTABLES -t nat -N "$CHAIN"
                    $_IPTABLES -t nat -A "$CHAIN" -p tcp --dport 445 -j MASQUERADE
                    $_IPTABLES -t nat -A "$CHAIN" -p tcp --dport 139 -j MASQUERADE
                    $_IPTABLES -t nat -A "$CHAIN" -p udp --dport 138 -j MASQUERADE
                    $_IPTABLES -t nat -A "$CHAIN" -p udp --dport 137 -j MASQUERADE
                    $_IPTABLES -t nat -A "$CHAIN" -p icmp --icmp-type 1 -j MASQUERADE
                    $_IPTABLES -t nat -A "$CHAIN" -j RETURN

                    for _VPN_NETWORK in $_VPN_NETWORKS; do
                        if [ -n "$_DESTINATION_NETWORK" ]; then
                            $_IPTABLES -t nat -A POSTROUTING -s "$_VPN_NETWORK" -d "$_DESTINATION_NETWORK" -o "$BRIDGE_INTERFACE" -j "$CHAIN"
                        else
                            $_IPTABLES -t nat -A POSTROUTING -s "$_VPN_NETWORK" -o "$BRIDGE_INTERFACE" -j "$CHAIN"
                        fi
                    done
                fi
            ;;
            "remove")
                if $_IPTABLES -t nat -nL "$CHAIN" >/dev/null 2>&1; then
                    for _VPN_NETWORK in $_VPN_NETWORKS; do
                        if [ -n "$_DESTINATION_NETWORK" ] && $_IPTABLES -t nat -C POSTROUTING -s "$_VPN_NETWORK" -d "$_DESTINATION_NETWORK" -o "$BRIDGE_INTERFACE" -j "$CHAIN" >/dev/null 2>&1; then
                            $_IPTABLES -t nat -D POSTROUTING -s "$_VPN_NETWORK" -d "$_DESTINATION_NETWORK" -o "$BRIDGE_INTERFACE" -j "$CHAIN"
                        fi

                        if $_IPTABLES -t nat -C POSTROUTING -s "$_VPN_NETWORK" -o "$BRIDGE_INTERFACE" -j "$CHAIN" >/dev/null 2>&1; then
                            $_IPTABLES -t nat -D POSTROUTING -s "$_VPN_NETWORK" -o "$BRIDGE_INTERFACE" -j "$CHAIN"
                        fi
                    done

                    $_IPTABLES -t nat -F "$CHAIN"
                    $_IPTABLES -t nat -X "$CHAIN"
                fi
            ;;
        esac
    done

    [ "$_RULES_ADDED" = 1 ] && logger -st "$SCRIPT_TAG" "Masquerading Samba connections from networks: $(echo "$VPN_NETWORKS $VPN_NETWORKS6" | awk '{$1=$1};1')"

    [ -n "$EXECUTE_COMMAND" ] && $EXECUTE_COMMAND "$1"

    lockfile unlock
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
