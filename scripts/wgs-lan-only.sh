#!/bin/sh
# Made by Jack'lul <jacklul.github.io>
#
# Prevent WireGuard server clients from accessing internet through the router
#

#jas-update=wgs-lan-only.sh
#shellcheck disable=SC2155
#shellcheck source=./common.sh
readonly common_script="$(dirname "$0")/common.sh"
if [ -f "$common_script" ]; then . "$common_script"; else { echo "$common_script not found"; exit 1; } fi

WG_INTERFACES="wgs1" # WireGuard server interfaces to set rules for (find it through 'nvram show | grep wgs' or 'ifconfig' command)
BRIDGE_INTERFACE="br0" # the bridge interface to limit access to, by default only LAN bridge (br0) interface, use br+ to also allow access to guest networks
EXECUTE_COMMAND="" # execute a command after firewall rules are applied or removed (receives arguments: $1 = action - add/remove)
RUN_EVERY_MINUTE= # verify that the rules are still set (true/false), empty means false when service-event script is available but otherwise true

load_script_config

for_iptables="iptables"
[ "$(nvram get ipv6_service)" != "disabled" ] && for_iptables="$for_iptables ip6tables"

firewall_rules() {
    [ -z "$WG_INTERFACES" ] && { logecho "Error: WireGuard interfaces are not set"; exit 1; }
    [ -z "$BRIDGE_INTERFACE" ] && { logecho "Error: Bridge interface is not set"; exit 1; }

    lockfile lockwait

    for _iptables in $for_iptables; do
        case "$1" in
            "add")
                for _wg_interface in $WG_INTERFACES; do
                    if ! $_iptables -C "WGSF" -i "$_wg_interface" ! -o "$BRIDGE_INTERFACE" -j REJECT > /dev/null 2>&1; then
                        $_iptables -I "WGSF" -i "$_wg_interface" ! -o "$BRIDGE_INTERFACE" -j REJECT && _rules_action=1 || _rules_error=1
                    fi
                done
            ;;
            "remove")
                for _wg_interface in $WG_INTERFACES; do
                    if $_iptables -C "WGSF" -i "$_wg_interface" ! -o "$BRIDGE_INTERFACE" -j REJECT > /dev/null 2>&1; then
                        $_iptables -D "WGSF" -i "$_wg_interface" ! -o "$BRIDGE_INTERFACE" -j REJECT && _rules_action=-1 || _rules_error=1
                    fi
                done
            ;;
        esac
    done

    [ -n "$_rules_error" ] && logecho "Errors detected while modifying firewall rules ($1)"

    if [ -n "$_rules_action" ]; then
        if [ "$_rules_action" = 1 ]; then
            logecho "Restricting WireGuard server ($WG_INTERFACES) clients to allow only access to interface '$BRIDGE_INTERFACE'" true
        else
            logecho "Restored internet access for WireGuard server ($WG_INTERFACES) clients" true
        fi
    fi

    [ -n "$EXECUTE_COMMAND" ] && [ -n "$_rules_action" ] && $EXECUTE_COMMAND "$1"

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
