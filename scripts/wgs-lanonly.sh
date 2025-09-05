#!/bin/sh
# Made by Jack'lul <jacklul.github.io>
#
# Prevent WireGuard server clients from accessing internet through the router
#

#jas-update=wgs-lanonly.sh
#shellcheck disable=SC2155
#shellcheck source=./common.sh
readonly common_script="$(dirname "$0")/common.sh"
if [ -f "$common_script" ]; then . "$common_script"; else { echo "$common_script not found"; exit 1; } fi

INTERFACE="wgs1" # WireGuard server interface (find it through 'nvram show | grep wgs' or 'ifconfig' command)
BRIDGE_INTERFACE="br0" # the bridge interface to limit access to, by default only LAN bridge ("br0") interface, use br+ to also allow access to guest networks
EXECUTE_COMMAND="" # execute a command after firewall rules are applied or removed (receives arguments: $1 = action)
RUN_EVERY_MINUTE= # verify that the rules are still set (true/false), empty means false when service-event script is available but otherwise true

load_script_config

readonly CHAIN="WGS_LANONLY"
for_iptables="iptables"
[ "$(nvram get ipv6_service)" != "disabled" ] && for_iptables="$for_iptables ip6tables"

firewall_rules() {
    [ -z "$INTERFACE" ] && { logger -st "$script_name" "Error: Target interface is not set"; exit 1; }
    [ -z "$BRIDGE_INTERFACE" ] && { logger -st "$script_name" "Error: Bridge interface is not set"; exit 1; }

    lockfile lockwait

    _rules_modified=0
    for _iptables in $for_iptables; do
        case "$1" in
            "add")
                if ! $_iptables -nL "$CHAIN" > /dev/null 2>&1; then
                    _rules_modified=1

                    _forward_start="$($_iptables -nL FORWARD --line-numbers | grep -E "all.*state RELATED,ESTABLISHED" | tail -1 | awk '{print $1}')"
                    _forward_start_plus="$((_forward_start+1))"

                    $_iptables -N "$CHAIN"
                    $_iptables -A "$CHAIN" ! -o "$BRIDGE_INTERFACE" -j DROP
                    $_iptables -A "$CHAIN" -j RETURN

                    $_iptables -I FORWARD "$_forward_start_plus" -i "$INTERFACE" -j "$CHAIN"
                fi
            ;;
            "remove")
                if $_iptables -nL "$CHAIN" > /dev/null 2>&1; then
                    _rules_modified=-1

                    $_iptables -D FORWARD -i "$INTERFACE" -j "$CHAIN"

                    $_iptables -F "$CHAIN"
                    $_iptables -X "$CHAIN"
                fi
            ;;
        esac
    done

    [ "$_rules_modified" = 1 ] && logger -st "$script_name" "Restricting WireGuard server to only allow LAN access"

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
