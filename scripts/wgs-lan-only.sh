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

WG_INTERFACES="" # WireGuard server interfaces to set rules for (find it through 'ifconfig' command), empty means auto detect
BRIDGE_INTERFACE="" # the bridge interface to limit access to, set 'br+' to also allow access to guest networks, empty means set to LAN bridge interface
EXECUTE_COMMAND="" # execute a command after firewall rules are applied or removed (receives arguments: $1 = action - add/remove)
RUN_EVERY_MINUTE= # verify that the rules are still set (true/false), empty means false when service-event script is available but otherwise true
RETRY_ON_ERROR=false # retry setting the rules on error (once per run)

load_script_config

firewall_rules() {
    if [ -z "$WG_INTERFACES" ]; then
        if [ "$(nvram get wgs_enable)" = "1" ]; then
            WG_INTERFACES="wgs+"
        fi

        [ -z "$WG_INTERFACES" ] && { echo "Error: WG_INTERFACES is not set"; exit 1; }
    fi

    [ -z "$BRIDGE_INTERFACE" ] && BRIDGE_INTERFACE="$(nvram get lan_ifname)"

    lockfile lockwait

    _for_iptables="iptables"
    [ "$(nvram get ipv6_service)" != "disabled" ] && _for_iptables="$_for_iptables ip6tables"

    modprobe xt_comment

    _rules_action=
    _rules_error=
    for _iptables in $_for_iptables; do
        case "$1" in
            "add")
                for _wg_interface in $WG_INTERFACES; do
                    if
                        ! $_iptables -C "WGSF" -i "$_wg_interface" ! -o "$BRIDGE_INTERFACE" -j REJECT \
                            -m comment --comment "jas-$script_name" > /dev/null 2>&1
                    then
                        $_iptables -I "WGSF" -i "$_wg_interface" ! -o "$BRIDGE_INTERFACE" -j REJECT \
                            -m comment --comment "jas-$script_name" \
                                && _rules_action=1 || _rules_error=1
                    fi
                done
            ;;
            "remove")
                remove_iptables_rules_by_comment "filter" && _rules_action=-1
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
    [ -z "$_rules_error" ] && return 0 || return 1
}

case "$1" in
    "run")
        firewall_rules add || { [ "$RETRY_ON_ERROR" = true ] && firewall_rules add; }
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
