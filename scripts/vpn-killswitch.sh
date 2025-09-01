#!/bin/sh
# Made by Jack'lul <jacklul.github.io>
#
# Prevent access to internet without VPN connection
#
# Based on:
#  https://github.com/ZebMcKayhan/WireguardManager/blob/main/wg_manager.sh
#

#jas-update=vpn-killswitch.sh
#shellcheck disable=SC2155
#shellcheck source=./common.sh
readonly common_script="$(dirname "$0")/common.sh"
if [ -f "$common_script" ]; then . "$common_script"; else { echo "$common_script not found"; exit 1; } fi

BRIDGE_INTERFACES="br+" # the bridge interface to set rules for, by default affects all "br" interfaces (which also includes guest networks), separated by spaces
EXECUTE_COMMAND="" # execute a command after firewall rules are applied or removed (receives arguments: $1 = action)
RUN_EVERY_MINUTE= # verify that the rules are still set (true/false), empty means false when service-event script is available but otherwise true

load_script_config

readonly CHAIN="VPN_KILLSWITCH"
for_iptables="iptables"
[ "$(nvram get ipv6_service)" != "disabled" ] && for_iptables="$for_iptables ip6tables"

get_wan_interface() {
    _interface="$(nvram get wan0_ifname)"

    if [ "$(nvram get wan0_gw_ifname)" != "$_interface" ]; then
        _interface=$(nvram get wan0_gw_ifname)
    fi

    if [ -n "$(nvram get wan0_pppoe_ifname)" ]; then
        _interface="$(nvram get wan0_pppoe_ifname)"
    fi

    [ -z "$_interface" ] && { logger -st "$script_name" "Error: Couldn't get WAN interface name"; exit 1; }

    echo "$_interface"
}

verify_bridge_interfaces() {
    if echo "$BRIDGE_INTERFACES" | grep -Fq "br+"; then
        BRIDGE_INTERFACES="br+" # sanity set, just in case one sets "br0 br+ br23"
    else
        for _bridge_interface in $BRIDGE_INTERFACES; do
            if ! ip link show | grep -F ": $_bridge_interface" | grep -Fq "mtu"; then
                logger -st "$script_name" "Couldn't find matching bridge interface for $_bridge_interface"
                exit 1
            fi
        done
    fi
}

firewall_rules() {
    [ -z "$BRIDGE_INTERFACES" ] && { logger -st "$script_name" "Error: Bridge interfaces are not set"; exit 1; }

    lockfile lockwait

    _rules_modified=0
    for _iptables in $for_iptables; do
        case "$1" in
            "add")
                if ! $_iptables -nL "$CHAIN" >/dev/null 2>&1; then
                    _rules_modified=1

                    $_iptables -N "$CHAIN"
                    $_iptables -I "$CHAIN" -j REJECT

                    _wan_interface="$(get_wan_interface)"
                    verify_bridge_interfaces

                    for _bridge_interface in $BRIDGE_INTERFACES; do
                        $_iptables -I FORWARD -i "$_bridge_interface" -o "$_wan_interface" -j "$CHAIN"

                        logger -st "$script_name" "Enabled VPN Kill-switch on bridge interface: $_bridge_interface"
                    done
                fi
            ;;
            "remove")
                if $_iptables -nL "$CHAIN" >/dev/null 2>&1; then
                    _rules_modified=-1

                    _wan_interface="$(get_wan_interface)"
                    verify_bridge_interfaces

                    for _bridge_interface in $BRIDGE_INTERFACES; do
                        $_iptables -D FORWARD -i "$_bridge_interface" -o "$_wan_interface" -j "$CHAIN"

                        logger -st "$script_name" "Disabled VPN Kill-switch on bridge interface: $_bridge_interface"
                    done

                    $_iptables -F "$CHAIN"
                    $_iptables -X "$CHAIN"
                fi
            ;;
        esac
    done

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
