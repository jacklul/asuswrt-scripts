#!/bin/sh
# Made by Jack'lul <jacklul.github.io>
#
# Prevent access to the internet without VPN connection for LAN clients
#
# Based on:
#  https://github.com/ZebMcKayhan/WireguardManager/blob/main/wg_manager.sh
#

#jas-update=vpn-kill-switch.sh
#shellcheck disable=SC2155
#shellcheck source=./common.sh
readonly common_script="$(dirname "$0")/common.sh"
if [ -f "$common_script" ]; then . "$common_script"; else { echo "$common_script not found"; exit 1; } fi

TARGET_INTERFACES="" # the interfaces to set rules for, separated by spaces, empty means set to LAN bridge interface
WAN_INTERFACES="" # WAN interfaces to block the access to, separated by spaces, empty means auto detect
EXECUTE_COMMAND="" # execute a command after firewall rules are applied or removed (receives arguments: $1 = action - add/remove)
RUN_EVERY_MINUTE= # verify that the rules are still set (true/false), empty means false when service-event script is available but otherwise true
RETRY_ON_ERROR=false # retry to set the rules on error (only once per run)

load_script_config

firewall_rules() {
    if [ -z "$TARGET_INTERFACES" ]; then
        TARGET_INTERFACES="$(nvram get lan_ifname)"
    elif echo "$TARGET_INTERFACES" | grep -Fq "br+"; then
        TARGET_INTERFACES="br+" # sanity set, just in case one sets "br1 br+ br2"
    fi

    if [ -z "$WAN_INTERFACES" ]; then
        [ "$(nvram get wan0_state_t)" != "0" ] && WAN_INTERFACES="$WAN_INTERFACES $(get_wan_interface 0)"
        [ "$(nvram get wan1_state_t)" != "0" ] && WAN_INTERFACES="$WAN_INTERFACES $(get_wan_interface 1)"

        [ -z "$WAN_INTERFACES" ] && { logecho "Error: WAN_INTERFACES is not set"; exit 1; }
    fi

    lockfile lockwait

    _for_iptables="iptables"
    [ "$(nvram get ipv6_service)" != "disabled" ] && _for_iptables="$_for_iptables ip6tables"

    modprobe xt_comment

    _applied_interfaces=
    _rules_action=
    _rules_error=
    for _iptables in $_for_iptables; do
        case "$1" in
            "add")
                for _target_interface in $TARGET_INTERFACES; do
                    for _wan_interface in $WAN_INTERFACES; do
                        if
                            ! $_iptables -C FORWARD -i "$_target_interface" -o "$_wan_interface" -j REJECT \
                                -m comment --comment "jas-$script_name" > /dev/null 2>&1
                        then
                            $_iptables -I FORWARD -i "$_target_interface" -o "$_wan_interface" -j REJECT \
                                -m comment --comment "jas-$script_name" \
                                    && _rules_action=1 || _rules_error=1
                        fi
                    done
                done
            ;;
            "remove")
                remove_iptables_rules_by_comment "filter" && _rules_action=-1
            ;;
        esac
    done

    [ "$_rules_error" = 1 ] && logecho "Errors detected while modifying firewall rules ($1)"

    if [ -n "$_rules_action" ]; then
        if [ "$_rules_action" = 1 ]; then
            logecho "Enabled VPN Kill-switch on interfaces: $(echo "$WAN_INTERFACES" | awk '{$1=$1};1')" true
        else
            logecho "Disabled VPN Kill-switch on interfaces: $(echo "$WAN_INTERFACES" | awk '{$1=$1};1')" true
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
