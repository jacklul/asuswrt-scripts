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

TARGET_INTERFACES="br0" # the interfaces to set rules for, by default only LAN bridge (br0) interface, separated by spaces
WAN_INTERFACES="" # WAN interfaces to block the access to, when empty it will use the main WAN interface, separated by spaces
EXECUTE_COMMAND="" # execute a command after firewall rules are applied or removed (receives arguments: $1 = action - add/remove)
RUN_EVERY_MINUTE= # verify that the rules are still set (true/false), empty means false when service-event script is available but otherwise true

load_script_config

for_iptables="iptables"
[ "$(nvram get ipv6_service)" != "disabled" ] && for_iptables="$for_iptables ip6tables"

firewall_rules() {
    [ -z "$TARGET_INTERFACES" ] && { logecho "Error: Target interfaces are not set"; exit 1; }
    echo "$TARGET_INTERFACES" | grep -Fq "br+" && TARGET_INTERFACES="br+" # sanity set, just in case one sets "br0 br+ br23"

    lockfile lockwait

    [ -z "$WAN_INTERFACES" ] && WAN_INTERFACES="$(get_wan_interface 0)"
    [ -z "$WAN_INTERFACES" ] && { logecho "Error: Couldn't get WAN interface name"; exit 1; }

    for _iptables in $for_iptables; do
        case "$1" in
            "add")
                for _target_interface in $TARGET_INTERFACES; do
                    for _wan_interface in $WAN_INTERFACES; do
                        if ! $_iptables -C FORWARD -i "$_target_interface" -o "$_wan_interface" -j REJECT > /dev/null 2>&1; then
                            if $_iptables -I FORWARD -i "$_target_interface" -o "$_wan_interface" -j REJECT; then
                                _rules_action=1
                                ! echo "$_applied_interfaces" | grep -F " $_target_interface " && _applied_interfaces="$_applied_interfaces $_target_interface "
                            else
                                _rules_error=1
                            fi
                        fi
                    done
                done
            ;;
            "remove")
                for _target_interface in $TARGET_INTERFACES; do
                    for _wan_interface in $WAN_INTERFACES; do
                        if $_iptables -C FORWARD -i "$_target_interface" -o "$_wan_interface" -j REJECT > /dev/null 2>&1; then
                            if $_iptables -D FORWARD -i "$_target_interface" -o "$_wan_interface" -j REJECT; then
                                _rules_action=-1
                                ! echo "$_applied_interfaces" | grep -F " $_target_interface " && _applied_interfaces="$_applied_interfaces $_target_interface "
                            else
                                _rules_error=1
                            fi
                        fi
                    done
                done
            ;;
        esac
    done

    [ "$_rules_error" = 1 ] && logecho "Errors detected while modifying firewall rules ($1)"

    if [ -n "$_rules_action" ]; then
        if [ "$_rules_action" = 1 ]; then
            logecho "Enabled VPN Kill-switch on interfaces: $(echo "$_applied_interfaces" | awk '{$1=$1};1')" true
        else
            logecho "Disabled VPN Kill-switch on interfaces: $(echo "$_applied_interfaces" | awk '{$1=$1};1')" true
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
