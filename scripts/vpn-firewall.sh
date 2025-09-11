#!/bin/sh
# Made by Jack'lul <jacklul.github.io>
#
# Prevent other end of the VPN connection from accessing the router or LAN
#

#jas-update=vpn-firewall.sh
#shellcheck disable=SC2155
#shellcheck source=./common.sh
readonly common_script="$(dirname "$0")/common.sh"
if [ -f "$common_script" ]; then . "$common_script"; else { echo "$common_script not found"; exit 1; } fi

VPN_INTERFACES=""  # VPN interfaces to affect, separated by spaces, empty means auto detect
ALLOW_INPUT_PORTS="" # allow connections on these ports in the INPUT chain, in format 'tcp=80 udp=5000-6000 1050' (not specifying protocol means tcp+udp), separated by spaces
ALLOW_FORWARD_PORTS="" # allow connections on these ports in the FORWARD chain, in format 'tcp=80 udp=5000-6000 1050' (not specifying protocol means tcp+udp), separated by spaces
EXECUTE_COMMAND="" # execute a command after firewall rules are applied or removed (receives arguments: $1 = action - add/remove)
RUN_EVERY_MINUTE= # verify that the rules are still set (true/false), empty means false when service-event script is available but otherwise true

load_script_config

iptables_chain() {
    # inherited: _iptables
    _extra=""
    _has_error=""

    case "$2" in
        "INPUT")
            _chain="$CHAIN_INPUT"
            _allow_ports="$ALLOW_INPUT_PORTS"
            [ -n "$3" ] && _extra="-d $3"
            _chain_type="input"
        ;;
        "FORWARD")
            _chain="$CHAIN_FORWARD"
            _allow_ports="$ALLOW_FORWARD_PORTS"
            [ -n "$3" ] && _extra="! -d $3"
            _chain_type="forward"
        ;;
    esac

    case "$1" in
        "add")
            $_iptables -N "$_chain"

            #shellcheck disable=SC2086
            for _port in $_allow_ports; do
                _proto=""

                if echo "$_port" | grep -Fq "="; then
                    _proto="$(echo "$_port" | cut -d '=' -f 1 2> /dev/null)"
                    _port="$(echo "$_port" | cut -d '=' -f 2 2> /dev/null)"
                fi

                if echo "$_port" | grep -Fq ":"; then # Port range
                    if [ -z "$_proto" ]; then
                        $_iptables -A "$_chain" -p tcp --match multiport --dports "$_port" $_extra -j RETURN || _has_error=1
                        $_iptables -A "$_chain" -p udp --match multiport --dports "$_port" $_extra -j RETURN || _has_error=1
                    else
                        $_iptables -A "$_chain" -p "$_proto" --match multiport --dports "$_port" $_extra -j RETURN || _has_error=1
                    fi
                else
                    if [ -z "$_proto" ]; then
                        $_iptables -A "$_chain" -p tcp --dport "$_port" $_extra -j RETURN || _has_error=1
                        $_iptables -A "$_chain" -p udp --dport "$_port" $_extra -j RETURN || _has_error=1
                    else
                        $_iptables -A "$_chain" -p "$_proto" --dport "$_port" $_extra -j RETURN || _has_error=1
                    fi
                fi
            done

            [ -n "$_allow_ports" ] && logecho "Allowed ports in the $_chain_type chain: $(echo "$_allow_ports" | awk '{$1=$1};1')" true

            $_iptables -A "$_chain" -j DROP || _has_error=1
        ;;
        "remove")
            $_iptables -F "$_chain"
            $_iptables -X "$_chain" || _has_error=1
        ;;
    esac

    [ -n "$_has_error" ] && return 1 || return 0
}

iptables_rule() {
    # inherited: _iptables
    _interface="$3"
    _num="$4"
    _has_error=""

    case "$1" in
        "add")
            _action="-I"
        ;;
        "remove")
            _action="-D"
        ;;
    esac

    case "$2" in
        "INPUT")
            _chain="INPUT"
            _target_chain="$CHAIN_INPUT"
            _chain_wgs="WGCI"
            _chain_ovpn="OVPNCI"
        ;;
        "FORWARD")
            _chain="FORWARD"
            _target_chain="$CHAIN_FORWARD"
            _chain_wgs="WGCF"
            _chain_ovpn="OVPNCF"
        ;;
    esac

    if echo "$_interface" | grep -Fq 'wgs'; then
        $_iptables "$_action" "$_chain_wgs" -i "$_interface" -j "$_target_chain" || _has_error=1
    elif echo "$_interface" | grep -Fq 'tun1'; then     
        $_iptables "$_action" "$_chain_ovpn" -i "$_interface" -j "$_target_chain" || _has_error=1    
    elif [ -n "$_num" ]; then
        $_iptables "$_action" "$_chain" "$_num" -i "$_interface" -j "$_target_chain" || _has_error=1
    else
        $_iptables "$_action" "$_chain" -i "$_interface" -j "$_target_chain" || _has_error=1
    fi

    [ -n "$_has_error" ] && return 1 || return 0
}

firewall_rules() {
    if [ -z "$VPN_INTERFACES" ]; then
        vpnc_profiles="$(get_vpnc_clientlist | awk -F '>' '{print $6, $2}' | grep "^1")" # get only active ones

        if echo "$vpnc_profiles" | grep -Fq "WireGuard"; then
            VPN_INTERFACES="$VPN_INTERFACES wgc+"
        fi

        if echo "$vpnc_profiles" | grep -Fq "OpenVPN"; then
            VPN_INTERFACES="$VPN_INTERFACES tun1+"
        fi

        [ -z "$VPN_INTERFACES" ] && { echo "Error: VPN_INTERFACES is not set"; exit 1; }
    fi

    lockfile lockwait

    readonly CHAIN_INPUT="jas-${script_name}-input"
    readonly CHAIN_FORWARD="jas-${script_name}-forward"
    for_iptables="iptables"
    [ "$(nvram get ipv6_service)" != "disabled" ] && for_iptables="$for_iptables ip6tables"

    for _iptables in $for_iptables; do
        if [ "$_iptables" = "ip6tables" ]; then
            _router_ip="$(nvram get ipv6_rtr_addr)"
        else
            _router_ip="$(nvram get lan_ipaddr)"
        fi

        case "$1" in
            "add")
                if ! $_iptables -nL "$CHAIN_INPUT" > /dev/null 2>&1; then
                    iptables_chain add INPUT || _rules_error=1

                    _input_start="$($_iptables -nvL INPUT --line-numbers | grep -E "WGSI .* all" | tail -1 | awk '{print $1}')"

                    if [ -n "$_input_start" ]; then
                        for _vpn_interface in $VPN_INTERFACES; do
                            iptables_rule add INPUT "$_vpn_interface" "$_input_start" && _rules_action=1 || _rules_error=1
                        done
                    else
                        logecho "Unable to find the 'target WGSI' rule in the INPUT filter chain"
                    fi
                fi

                if ! $_iptables -nL "$CHAIN_FORWARD" > /dev/null 2>&1; then
                    iptables_chain add FORWARD || _rules_error=1

                    _forward_start="$($_iptables -nvL FORWARD --line-numbers | grep -E "WGSF .* all" | tail -1 | awk '{print $1}')"

                    if [ -n "$_forward_start" ]; then
                        for _vpn_interface in $VPN_INTERFACES; do
                            iptables_rule add FORWARD "$_vpn_interface" "$_forward_start" && _rules_action=1 || _rules_error=1
                        done
                    else
                        logecho "Unable to find the 'target WGSF' rule in the FORWARD filter chain"
                    fi
                fi
            ;;
            "remove")
                if $_iptables -nL "$CHAIN_INPUT" > /dev/null 2>&1; then
                    for _vpn_interface in $VPN_INTERFACES; do
                        iptables_rule remove INPUT "$_vpn_interface" && _rules_action=-1 || _rules_error=1
                    done

                    iptables_chain remove INPUT || _rules_error=1
                fi

                if $_iptables -nL "$CHAIN_FORWARD" > /dev/null 2>&1; then
                    for _vpn_interface in $VPN_INTERFACES; do
                        iptables_rule remove FORWARD "$_vpn_interface" && _rules_action=-1 || _rules_error=1
                    done

                    iptables_chain remove FORWARD || _rules_error=1
                fi
            ;;
        esac
    done

    [ "$_rules_error" = 1 ] && logecho "Errors detected while modifying firewall rules ($1)"

    if [ -n "$_rules_action" ]; then
        if [ "$_rules_action" = 1 ]; then
            logecho "Blocking connections coming from VPN interfaces: $(echo "$VPN_INTERFACES" | awk '{$1=$1};1')" true
        else
            logecho "Stopped blocking connections coming from VPN interfaces: $(echo "$VPN_INTERFACES" | awk '{$1=$1};1')" true
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
