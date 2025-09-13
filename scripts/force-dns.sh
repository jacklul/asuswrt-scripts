#!/bin/sh
# Made by Jack'lul <jacklul.github.io>
#
# Force LAN to use specified DNS server
#
# Can set rules depending on whenever specific interface is available and define a fallback DNS server when it is not
# Can also prevent clients from querying router's DNS server while the rules are applied
#
# Based on DNS Director feature from Asuswrt-Merlin:
#  https://github.com/RMerl/asuswrt-merlin.ng/wiki/DNS-Director
#

#jas-update=force-dns.sh
#shellcheck disable=SC2155
#shellcheck source=./common.sh
readonly common_script="$(dirname "$0")/common.sh"
if [ -f "$common_script" ]; then . "$common_script"; else { echo "$common_script not found"; exit 1; } fi

DNS_SERVER="" # when left empty it will use DNS server set on DHCP page or router's address if those fields is empty
DNS_SERVER6="" # same as DNS_SERVER but for IPv6, when left empty it will use DNS server set on IPv6 page or router's address if those fields is empty, set to "block" to block IPv6 DNS traffic
PERMIT_MAC="" # space separated allowed MAC addresses to bypass forced DNS
PERMIT_IP="" # space separated allowed IPv4 addresses to bypass forced DNS, ranges supported
PERMIT_IP6="" # same as PERMIT_IP but for IPv6
TARGET_INTERFACES="br+" # the target interfaces to set rules for, separated by spaces, by default all bridge interfaces (includes guest networks)
REQUIRE_INTERFACE="" # rules will be removed if this interface is not up, wildcards accepted, set this to "usb*" when using usb-network script and Pi-hole on USB connected Raspberry Pi
FALLBACK_DNS_SERVER="" # set to this DNS server (IPv4) when interface defined in REQUIRE_INTERFACE does not exist
FALLBACK_DNS_SERVER6="" # same as FALLBACK_DNS_SERVER but for IPv6
EXECUTE_COMMAND="" # execute a command after firewall rules are applied or removed (receives arguments: $1 = action - add/remove)
BLOCK_ROUTER_DNS=false # block access to router's DNS server while the rules are set, best used with REQUIRE_INTERFACE and "Advertise router as DNS" option
VERIFY_DNS=false # verify that the DNS server is working before applying
VERIFY_DNS_FALLBACK=false # verify that the DNS server is working before applying (fallback only)
VERIFY_DNS_DOMAIN=asus.com # domain used when checking if DNS server is working
RUN_EVERY_MINUTE= # verify that the rules are still set (true/false), empty means false when service-event script is available but otherwise true

load_script_config

router_ip="$(nvram get lan_ipaddr)"
router_ip6="$(nvram get ipv6_rtr_addr)"
ipv6_service="$(nvram get ipv6_service)"

if [ -z "$DNS_SERVER" ]; then
    dhcp_dns1="$(nvram get dhcp_dns1_x)"
    dhcp_dns2="$(nvram get dhcp_dns2_x)"

    if [ -n "$dhcp_dns1" ]; then
        DNS_SERVER="$dhcp_dns1"
    elif [ -n "$dhcp_dns2" ]; then
        DNS_SERVER="$dhcp_dns2"
    else
        DNS_SERVER="$router_ip"
    fi
fi

if [ "$ipv6_service" != "disabled" ]; then
    ipv6_dns1="$(nvram get ipv6_dns1)"
    ipv6_dns2="$(nvram get ipv6_dns2)"
    ipv6_dns3="$(nvram get ipv6_dns3)"
    ipv6_dns1_x="$(nvram get ipv6_dns1_x)"

    if [ -n "$ipv6_dns1" ]; then
        DNS_SERVER="$ipv6_dns1"
    elif [ -n "$ipv6_dns2" ]; then
        DNS_SERVER="$ipv6_dns2"
    elif [ -n "$ipv6_dns3" ]; then
        DNS_SERVER="$ipv6_dns3"
    elif [ -n "$ipv6_dns1_x" ]; then
        DNS_SERVER="$ipv6_dns1_x"
    elif [ -z "$DNS_SERVER6" ]; then
        DNS_SERVER6="$router_ip6"
    elif [ "$DNS_SERVER6" = "block" ]; then
        DNS_SERVER6=""
    fi
fi

# These "iptables_" functions are based on code from YazFi (https://github.com/jackyaz/YazFi) then modified using code from dnsfiler.c
iptables_chains() {
    _rules_error=

    for _iptables in $for_iptables; do
        case "$1" in
            "add")
                if ! $_iptables -nL "$CHAIN_DOT" > /dev/null 2>&1; then
                    # You would think there might be a possible race condition with vpn-firewall here and we should add one space
                    # before 'state' but in reality it's good that this rule is inserted after vpn-firewall's rule
                    _forward_start="$($_iptables -nvL FORWARD --line-numbers | grep -E "all .* state RELATED,ESTABLISHED" | tail -1 | awk '{print $1}')"

                    if [ -n "$_forward_start" ]; then
                        _forward_start="$((_forward_start+1))"

                        $_iptables -N "$CHAIN_DOT"

                        for _target_interface in $TARGET_INTERFACES; do
                            $_iptables -I FORWARD "$_forward_start" -i "$_target_interface" -p tcp -m tcp --dport 853 -j "$CHAIN_DOT" || _rules_error=1
                            _forward_start="$((_forward_start+1))"
                        done
                    else
                        logecho "Unable to find the 'state RELATED,ESTABLISHED' rule in the FORWARD FILTER chain"
                    fi
                fi

                if ! $_iptables -t nat -nL "$CHAIN_DNAT" > /dev/null 2>&1; then
                    _prerouting_start="$($_iptables -t nat -nvL PREROUTING --line-numbers | grep -E "VSERVER .* all" | tail -1 | awk '{print $1}')"

                    if [ -n "$_prerouting_start" ]; then
                        _prerouting_start="$((_prerouting_start+1))"

                        $_iptables -t nat -N "$CHAIN_DNAT"

                        for _target_interface in $TARGET_INTERFACES; do
                            $_iptables -t nat -I PREROUTING "$_prerouting_start" -i "$_target_interface" -p tcp -m tcp --dport 53 -j "$CHAIN_DNAT" || _rules_error=1
                            $_iptables -t nat -I PREROUTING "$_prerouting_start" -i "$_target_interface" -p udp -m udp --dport 53 -j "$CHAIN_DNAT" || _rules_error=1
                            _prerouting_start="$((_prerouting_start+2))"
                        done
                    else
                        logecho "Unable to find the 'target VSERVER' rule in the PREROUTING NAT chain"
                    fi
                fi

                if [ "$BLOCK_ROUTER_DNS" = true ] && ! $_iptables -nL "$CHAIN_BLOCK" > /dev/null 2>&1; then
                    if [ "$_iptables" = "ip6tables" ]; then
                        _router_ip="$router_ip6"
                    else
                        _router_ip="$router_ip"
                    fi

                    _input_start="$($_iptables -nvL INPUT --line-numbers | grep -E "all .* state INVALID" | tail -1 | awk '{print $1}')"

                    if [ -n "$_input_start" ]; then
                        _input_start="$((_input_start+1))"

                        $_iptables -N "$CHAIN_BLOCK"

                        for _target_interface in $TARGET_INTERFACES; do
                            $_iptables -I INPUT "$_input_start" -i "$_target_interface" -p tcp -m tcp --dport 53 -d "$_router_ip" -j "$CHAIN_BLOCK" || _rules_error=1
                            $_iptables -I INPUT "$_input_start" -i "$_target_interface" -p udp -m udp --dport 53 -d "$_router_ip" -j "$CHAIN_BLOCK" || _rules_error=1
                            _input_start="$((_input_start+2))"
                        done
                    else
                        logecho "Unable to find the 'state INVALID' rule in the INPUT FILTER chain"
                    fi
                fi
            ;;
            "remove")
                if $_iptables -nL "$CHAIN_DOT" > /dev/null 2>&1; then
                    for _target_interface in $TARGET_INTERFACES; do
                        $_iptables -D FORWARD -i "$_target_interface" -p tcp -m tcp --dport 853 -j "$CHAIN_DOT" || _rules_error=1
                    done

                    $_iptables -F "$CHAIN_DOT"
                    $_iptables -X "$CHAIN_DOT" || _rules_error=1
                fi

                if $_iptables -t nat -nL "$CHAIN_DNAT" > /dev/null 2>&1; then
                    for _target_interface in $TARGET_INTERFACES; do
                        $_iptables -t nat -D PREROUTING -i "$_target_interface" -p udp -m udp --dport 53 -j "$CHAIN_DNAT" || _rules_error=1
                        $_iptables -t nat -D PREROUTING -i "$_target_interface" -p tcp -m tcp --dport 53 -j "$CHAIN_DNAT" || _rules_error=1
                    done

                    $_iptables -t nat -F "$CHAIN_DNAT"
                    $_iptables -t nat -X "$CHAIN_DNAT" || _rules_error=1
                fi

                if $_iptables -nL "$CHAIN_BLOCK" > /dev/null 2>&1; then
                    if [ "$_iptables" = "ip6tables" ]; then
                        _router_ip="$router_ip6"
                    else
                        _router_ip="$router_ip"
                    fi

                    for _target_interface in $TARGET_INTERFACES; do
                        $_iptables -D INPUT -i "$_target_interface" -p udp -m udp --dport 53 -d "$_router_ip" -j "$CHAIN_BLOCK" || _rules_error=1
                        $_iptables -D INPUT -i "$_target_interface" -p tcp -m tcp --dport 53 -d "$_router_ip" -j "$CHAIN_BLOCK" || _rules_error=1
                    done

                    $_iptables -F "$CHAIN_BLOCK"
                    $_iptables -X "$CHAIN_BLOCK" || _rules_error=1
                fi
            ;;
        esac
    done

    [ "$_rules_error" = 1 ] && logecho "Errors detected while modifying firewall chains ($1)"
}

iptables_rules() {
    _dns_server="$2"
    _dns_server6="$3"
    _rules_error=

    case "$1" in
        "add")
            _action="-A"
        ;;
        "remove")
            _action="-D"
        ;;
    esac

    for _iptables in $for_iptables; do
        _block_router_dns="$BLOCK_ROUTER_DNS"

        if [ "$_iptables" = "ip6tables" ]; then
            if [ -z "$DNS_SERVER6" ]; then
                $_iptables -t nat "$_action" "$CHAIN_DNAT" -j DNAT --to-destination 0.0.0.0
                $_iptables "$_action" "$CHAIN_DOT" -j REJECT
                continue
            fi

            _set_dns_server="$_dns_server6"
            _permit_ip="$PERMIT_IP6"
            _router_ip="$router_ip6"
        else
            _set_dns_server="$_dns_server"
            _permit_ip="$PERMIT_IP"
            _router_ip="$router_ip"
        fi

        [ "$_router_ip" = "$_set_dns_server" ] && _block_router_dns=false

        # When router is set as DNS server, add it to the list of allowed IPs if it's not there
        if [ -n "$_permit_ip" ] && ! echo "$_permit_ip" | grep -Fq "$_router_ip"; then
            _permit_ip="$_router_ip $_permit_ip"
        fi

        if [ -n "$PERMIT_MAC" ]; then
            for _mac in $PERMIT_MAC; do
                _mac="$(echo "$_mac" | awk '{$1=$1};1')"

                $_iptables -t nat "$_action" "$CHAIN_DNAT" -m mac --mac-source "$_mac" -j RETURN || _rules_error=1
                $_iptables "$_action" "$CHAIN_DOT" -m mac --mac-source "$_mac" -j RETURN || _rules_error=1

                if [ "$_block_router_dns" = true ]; then
                    $_iptables "$_action" "$CHAIN_BLOCK" -m mac --mac-source "$_mac" -j RETURN || _rules_error=1
                fi
            done
        fi

        if [ -n "$_permit_ip" ]; then
            if [ "${_permit_ip#*"-"}" != "$_permit_ip" ]; then # IP ranges found
                for _ip in $_permit_ip; do
                    _ip="$(echo "$_ip" | awk '{$1=$1};1')"

                    if [ "${_ip#*"-"}" != "$_ip" ]; then # IP range entry
                        $_iptables -t nat "$_action" "$CHAIN_DNAT" -m iprange --src-range "$_ip" -j RETURN || _rules_error=1
                        $_iptables "$_action" "$CHAIN_DOT" -m iprange --src-range "$_ip" -j RETURN || _rules_error=1

                        if [ "$_block_router_dns" = true ]; then
                            $_iptables "$_action" "$CHAIN_BLOCK" -m iprange --src-range "$_ip" -j RETURN || _rules_error=1
                        fi
                    else # single IP entry
                        $_iptables -t nat "$_action" "$CHAIN_DNAT" -s "$_ip" -j RETURN || _rules_error=1
                        $_iptables "$_action" "$CHAIN_DOT" -s "$_ip" -j RETURN || _rules_error=1

                        if [ "$_block_router_dns" = true ]; then
                            $_iptables "$_action" "$CHAIN_BLOCK" -s "$_ip" -j RETURN || _rules_error=1
                        fi
                    fi
                done
            else # no IP ranges found, conveniently iptables accept IPs separated by commas
                _permit_ip="$(echo "$_permit_ip" | tr ' ' ',' | awk '{$1=$1};1')"

                $_iptables -t nat "$_action" "$CHAIN_DNAT" -s "$_permit_ip" -j RETURN || _rules_error=1
                $_iptables "$_action" "$CHAIN_DOT" -s "$_permit_ip" -j RETURN || _rules_error=1

                if [ "$_block_router_dns" = true ]; then
                    $_iptables "$_action" "$CHAIN_BLOCK" -s "$_permit_ip" -j RETURN || _rules_error=1
                fi
            fi
        fi

        if [ "$_block_router_dns" = true ]; then
            $_iptables -t nat "$_action" "$CHAIN_DNAT" -d "$_router_ip" -j RETURN || _rules_error=1
        fi

        $_iptables -t nat "$_action" "$CHAIN_DNAT" ! -d "$_set_dns_server" -j DNAT --to-destination "$_set_dns_server" || _rules_error=1
        $_iptables "$_action" "$CHAIN_DOT" ! -d "$_set_dns_server" -j REJECT || _rules_error=1

        if [ "$_block_router_dns" = true ]; then
            $_iptables "$_action" "$CHAIN_BLOCK" -j REJECT
        fi
    done

    [ "$_rules_error" = 1 ] && logecho "Errors detected while modifying firewall rules ($1)"
}

rules_exist() {
    if iptables -t nat -nL "$CHAIN_DNAT" > /dev/null 2>&1 && iptables -nL "$CHAIN_DOT" > /dev/null 2>&1; then
        if iptables -t nat -C "$CHAIN_DNAT" ! -d "$1" -j DNAT --to-destination "$1" > /dev/null 2>&1; then
            return 0
        fi
    fi

    return 1
}

firewall_rules() {
    [ -z "$DNS_SERVER" ] && { logecho "Error: DNS_SERVER is not set"; exit 1; }
    [ -z "$TARGET_INTERFACES" ] && { logecho "Error: TARGET_INTERFACES is not set"; exit 1; }

    lockfile lockwait

    readonly CHAIN_DNAT="jas-${script_name}-dnat"
    readonly CHAIN_DOT="jas-${script_name}-dot"
    readonly CHAIN_BLOCK="jas-${script_name}-block"

    for_iptables="iptables"
    [ "$ipv6_service" != "disabled" ] && for_iptables="$for_iptables ip6tables"

    _rules_action=0
    case "$1" in
        "add")
            if ! rules_exist "$DNS_SERVER"; then
                _rules_action=1

                iptables_chains remove

                if [ "$VERIFY_DNS" = false ] || nslookup "$VERIFY_DNS_DOMAIN" "$DNS_SERVER" > /dev/null 2>&1; then
                    iptables_chains add
                    iptables_rules add "$DNS_SERVER" "$DNS_SERVER6"

                    _dns_server="$DNS_SERVER"
                    [ -n "$DNS_SERVER6" ] && _dns_server=" $DNS_SERVER6"

                    logecho "Forcing DNS servers: $_dns_server" true
                fi
            fi
        ;;
        "remove")
            if [ -n "$FALLBACK_DNS_SERVER" ]; then
                if ! rules_exist "$FALLBACK_DNS_SERVER"; then
                    _rules_action=-1

                    iptables_chains remove

                    if [ "$VERIFY_DNS_FALLBACK" = false ] || nslookup "$VERIFY_DNS_DOMAIN" "$FALLBACK_DNS_SERVER" > /dev/null 2>&1; then
                        iptables_chains add
                        iptables_rules add "$FALLBACK_DNS_SERVER" "$FALLBACK_DNS_SERVER6"

                        _fallback_dns_server="$FALLBACK_DNS_SERVER"
                        [ -n "$FALLBACK_DNS_SERVER6" ] && _fallback_dns_server=" $FALLBACK_DNS_SERVER6"

                        logecho "Forcing fallback DNS servers: $_fallback_dns_server" true
                    fi
                fi
            else
                if rules_exist "$DNS_SERVER" || rules_exist "$FALLBACK_DNS_SERVER"; then
                    _rules_action=-1

                    iptables_chains remove
                fi
            fi
        ;;
    esac

    [ -n "$EXECUTE_COMMAND" ] && [ -n "$_rules_action" ] && $EXECUTE_COMMAND "$1"

    lockfile unlock
}

case "$1" in
    "run")
        if [ -n "$REQUIRE_INTERFACE" ] && ! interface_exists "$REQUIRE_INTERFACE"; then
            firewall_rules remove
        else
            firewall_rules add
        fi
    ;;
    "fallback")
        if [ -n "$FALLBACK_DNS_SERVER" ]; then
            firewall_rules remove
        else
            logecho "Fallback DNS servers are not set!"
            exit 1
        fi
    ;;
    "start")
        { [ -z "$REQUIRE_INTERFACE" ] || interface_exists "$REQUIRE_INTERFACE" ; } && firewall_rules add

        # Set value of empty RUN_EVERY_MINUTE depending on situation
        execute_script_basename "service-event.sh" check && service_event_active=true
        [ -z "$RUN_EVERY_MINUTE" ] && [ -z "$service_event_active" ] && RUN_EVERY_MINUTE=true

        if [ "$RUN_EVERY_MINUTE" = true ]; then
            crontab_entry add "*/1 * * * * $script_path run"
        fi
    ;;
    "stop")
        crontab_entry delete
        FALLBACK_DNS_SERVER="" # prevent changing to fallback instead of removing everything...
        firewall_rules remove
    ;;
    "restart")
        sh "$script_path" stop
        sh "$script_path" start
    ;;
    *)
        echo "Usage: $0 run|start|stop|restart|fallback"
        exit 1
    ;;
esac
