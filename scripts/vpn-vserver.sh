#!/bin/sh
# Made by Jack'lul <jacklul.github.io>
#
# Allow VPN clients to utilize virtual server/port forwarding rules
#

#jas-update=vpn-vserver.sh
#shellcheck disable=SC2155
#shellcheck source=./common.sh
readonly common_script="$(dirname "$0")/common.sh"
if [ -f "$common_script" ]; then . "$common_script"; else { echo "$common_script not found"; exit 1; } fi

VPN_ADDRESSES="" # VPN addresses (IPv4) to affect, in format '10.10.10.10', separated by spaces, empty means auto detect
VPN_ADDRESSES6="" # same as VPN_ADDRESSES but for IPv6, separated by spaces, no auto detect available
EXECUTE_COMMAND="" # execute a command after firewall rules are applied or removed (receives arguments: $1 = action - add/remove)
RUN_EVERY_MINUTE= # verify that the rules are still set (true/false), empty means false when service-event script is available but otherwise true
RETRY_ON_ERROR=false # retry to set the rules on error (only once per run)

load_script_config

get_interface_address() {
    ip addr show "$1" | grep inet | awk '{print $2}' | cut -d '/' -f 1
}

firewall_rules() {
    if { [ -z "$VPN_ADDRESSES" ] && [ -z "$VPN_ADDRESSES6" ] ; }; then
        for _unit in 5 4 3 2 1; do
            if [ "$(nvram get wgc${_unit}_enable)" = "1" ]; then
                _address="$(get_interface_address "wgc${_unit}")"

                if [ -n "$_address" ]; then
                    VPN_ADDRESSES="$VPN_ADDRESSES $_address"
                fi
            fi
        done

        for _unit in 5 4 3 2 1; do
            if [ "$(nvram get vpn_client${_unit}_state)" = "2" ]; then
                _ifname="$(nvram get vpn_client${_unit}_if)"
                _address="$(get_interface_address "${_ifname}1${_unit}")"

                if [ -n "$_address" ]; then
                    VPN_ADDRESSES="$VPN_ADDRESSES $_address"
                fi
            fi
        done

        { [ -z "$VPN_ADDRESSES" ] && [ -z "$VPN_ADDRESSES6" ] ; } && { echo "Error: VPN_ADDRESSES/VPN_ADDRESSES6 is not set"; exit 1; }
    fi

    lockfile lockwait

    _for_iptables="iptables"
    [ "$(nvram get ipv6_service)" != "disabled" ] && _for_iptables="$_for_iptables ip6tables"

    _rules_action=
    _rules_error=
    for _iptables in $_for_iptables; do
        if [ "$_iptables" = "ip6tables" ]; then
            _vpn_addresses="$VPN_ADDRESSES6"
        else
            _vpn_addresses="$VPN_ADDRESSES"
        fi

        [ -z "$_vpn_addresses" ] && continue

        case "$1" in
            "add")
                _vserver_start="$($_iptables -t nat -nvL PREROUTING --line-numbers | grep -E "VSERVER .* all" | tail -1 | awk '{print $1}')"

                if [ -n "$_vserver_start" ]; then
                    for _vpn_address in $_vpn_addresses; do
                        if ! $_iptables -t nat -C PREROUTING -d "$_vpn_address" -j VSERVER > /dev/null 2>&1; then
                            _vserver_start=$((_vserver_start+1))
                            $_iptables -t nat -I PREROUTING "$_vserver_start" -d "$_vpn_address" -j VSERVER && _rules_action=1 || _rules_error=1
                        fi
                    done
                else
                    logecho "Unable to find the 'VSERVER' rule in the PREROUTING NAT chain"
                    _rules_error=1
                fi
            ;;
            "remove")
                for _vpn_address in $_vpn_addresses; do
                    $_iptables -t nat -D PREROUTING -d "$_vpn_address" -j VSERVER > /dev/null 2>&1 && _rules_action=-1
                done
            ;;
        esac
    done

    [ "$_rules_error" = 1 ] && logecho "Errors detected while modifying firewall rules ($1)"

    if [ -n "$_rules_action" ]; then
        if [ "$_rules_action" = 1 ]; then
            logecho "Enabled virtual server rules for VPN addresses: $(echo "$VPN_ADDRESSES $VPN_ADDRESSES6" | awk '{$1=$1};1')" true
        else
            logecho "Disabled virtual server rules for VPN addresses: $(echo "$VPN_ADDRESSES $VPN_ADDRESSES6" | awk '{$1=$1};1')" true
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
