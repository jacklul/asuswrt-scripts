#!/bin/sh
# Made by Jack'lul <jacklul.github.io>
#
# Enables VPN clients to access Samba shares in LAN
#

#jas-update=vpn-samba.sh
#shellcheck disable=SC2155
#shellcheck source=./common.sh
readonly common_script="$(dirname "$0")/common.sh"
if [ -f "$common_script" ]; then . "$common_script"; else { echo "$common_script not found"; exit 1; } fi

VPN_NETWORKS="10.6.0.0/24 10.8.0.0/24 10.10.10.0/24" # VPN networks (IPv4) to allow access to Samba from, separated by spaces
VPN_NETWORKS6="" # VPN networks (IPv6) to allow access to Samba from, separated by spaces
BRIDGE_INTERFACE="br0" # the bridge interface to set rules for, by default only LAN bridge ("br0") interface
EXECUTE_COMMAND="" # execute a command after firewall rules are applied or removed (receives arguments: $1 = action)
RUN_EVERY_MINUTE= # verify that the rules are still set (true/false), empty means false when service-event script is available but otherwise true

load_script_config

readonly CHAIN="VPN_SAMBA"
for_iptables="iptables"
[ "$(nvram get ipv6_service)" != "disabled" ] && for_iptables="$for_iptables ip6tables"

get_destination_network() {
    "$1" -t nat -nvL POSTROUTING --line-numbers | grep -E " MASQUERADE .*$BRIDGE_INTERFACE" | head -1 | awk '{print $9}'
}

firewall_rules() {
    [ -z "$BRIDGE_INTERFACE" ] && { logger -st "$script_name" "Error: Bridge interface is not set"; exit 1; }
    [ -z "$VPN_NETWORKS" ] && { logger -st "$script_name" "Error: Allowed VPN networks are not set"; exit 1; }

    lockfile lockwait

    _rules_modified=0
    for _iptables in $for_iptables; do
        if [ "$_iptables" = "ip6tables" ]; then
            _vpn_networks="$VPN_NETWORKS6"
        else
            _vpn_networks="$VPN_NETWORKS"
        fi

        [ -z "$_vpn_networks" ] && continue

        case "$1" in
            "add")
                if ! $_iptables -t nat -nL "$CHAIN" > /dev/null 2>&1; then
                    _rules_modified=1

                    $_iptables -t nat -N "$CHAIN"
                    $_iptables -t nat -A "$CHAIN" -p tcp --dport 445 -j MASQUERADE
                    $_iptables -t nat -A "$CHAIN" -p tcp --dport 139 -j MASQUERADE
                    $_iptables -t nat -A "$CHAIN" -p udp --dport 138 -j MASQUERADE
                    $_iptables -t nat -A "$CHAIN" -p udp --dport 137 -j MASQUERADE
                    $_iptables -t nat -A "$CHAIN" -p icmp --icmp-type 1 -j MASQUERADE
                    $_iptables -t nat -A "$CHAIN" -j RETURN

                    _destination_network="$(get_destination_network "$_iptables")"

                    for _vpn_network in $_vpn_networks; do
                        if [ -n "$_destination_network" ]; then
                            $_iptables -t nat -A POSTROUTING -s "$_vpn_network" -d "$_destination_network" -o "$BRIDGE_INTERFACE" -j "$CHAIN"
                        else
                            $_iptables -t nat -A POSTROUTING -s "$_vpn_network" -o "$BRIDGE_INTERFACE" -j "$CHAIN"
                        fi
                    done
                fi
            ;;
            "remove")
                if $_iptables -t nat -nL "$CHAIN" > /dev/null 2>&1; then
                    _rules_modified=-1

                    for _vpn_network in $_vpn_networks; do
                        _destination_network="$(get_destination_network "$_iptables")"

                        if [ -n "$_destination_network" ] && $_iptables -t nat -C POSTROUTING -s "$_vpn_network" -d "$_destination_network" -o "$BRIDGE_INTERFACE" -j "$CHAIN" > /dev/null 2>&1; then
                            $_iptables -t nat -D POSTROUTING -s "$_vpn_network" -d "$_destination_network" -o "$BRIDGE_INTERFACE" -j "$CHAIN"
                        fi

                        if $_iptables -t nat -C POSTROUTING -s "$_vpn_network" -o "$BRIDGE_INTERFACE" -j "$CHAIN" > /dev/null 2>&1; then
                            $_iptables -t nat -D POSTROUTING -s "$_vpn_network" -o "$BRIDGE_INTERFACE" -j "$CHAIN"
                        fi
                    done

                    $_iptables -t nat -F "$CHAIN"
                    $_iptables -t nat -X "$CHAIN"
                fi
            ;;
        esac
    done

    [ "$_rules_modified" = 1 ] && logger -st "$script_name" "Masquerading Samba connections from networks: $(echo "$VPN_NETWORKS $VPN_NETWORKS6" | awk '{$1=$1};1')"

    [ -n "$EXECUTE_COMMAND" ] && [ "$_rules_modified" -ne 0 ] && $EXECUTE_COMMAND "$1"

    lockfile unlock
}

case "$1" in
    "run")
        firewall_rules add
    ;;
    "start")
        firewall_rules add

        # Set value of empty RUN_EVERY_MINUTE depending on situation
        execute_script_basename "service-event.sh" check && service_event_active=true
        [ -z "$RUN_EVERY_MINUTE" ] && [ -z "$service_event_active" ] && RUN_EVERY_MINUTE=true

        if [ "$RUN_EVERY_MINUTE" = true ]; then
            crontab_entry add "*/1 * * * * $script_path run"
        fi
    ;;
    "stop")
        crontab_entry delete
        firewall_rules remove
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
