#!/bin/sh
# Made by Jack'lul <jacklul.github.io>
#
# Forces LAN to use specified DNS server
#
# Implements DNS Director feature from AsusWRT-Merlin:
#  https://github.com/RMerl/asuswrt-merlin.ng/wiki/DNS-Director
#
# Can set rules depending on whenever specific interface is available and define a fallback DNS server when it is not.
# Can also prevent clients from querying router's DNS server while the rules are applied.
#
# If you need per-device DNS settings then these will help you write your own script (which you can execute via EXECUTE_COMMAND variable):
#  iptables -I "FORCEDNS" -m mac --mac-source "d9:32:cb:d0:fe:fe" -j DNAT --to-destination "1.1.1.1"
#  iptables -I "FORCEDNS_DOT" -m mac --mac-source "d9:32:cb:d0:fe:fe" ! -d "1.1.1.1" -j REJECT
#

#shellcheck disable=SC2155

DNS_SERVER="" # when left empty will use DNS server set in DHCP DNS1 (or router's address if that field is empty)
DNS_SERVER6="" # same as DNS_SERVER but for IPv6, when left empty will use router's address, set to "block" to block IPv6 DNS traffic
PERMIT_MAC="" # space/comma separated allowed MAC addresses to bypass forced DNS
PERMIT_IP="" # space/comma separated allowed v4 IPs to bypass forced DNS, ranges supported
PERMIT_IP6="" # space/comma separated allowed v6 IPs to bypass forced DNS, ranges supported
BRIDGE_INTERFACE="br+" # the bridge interface to set rules for, by default affects all "br" interfaces
REQUIRE_INTERFACE="" # rules will be removed if this interface does not exist in /sys/class/net/, wildcards accepted
FALLBACK_DNS_SERVER="" # set to this DNS server when interface defined in REQUIRE_INTERFACE does not exist
FALLBACK_DNS_SERVER6="" # set to this DNS server (IPv6) when interface defined in REQUIRE_INTERFACE does not exist
EXECUTE_COMMAND="" # execute a command after rules are applied or removed, will pass argument with action (add or remove)
BLOCK_ROUTER_DNS=false # block access to router's DNS server while the rules are set, best used with REQUIRE_INTERFACE and "Advertise router as DNS" option
USE_WATCHDOG=true # should we monitor the syslog for firewall restart event to restore the rules after
CACHE_FILE="/tmp/last_firewall_restart" # where to store last log line when firewall was restarted
WATCHDOG_SLEEP=1 # the amount of time to sleep each loop when monitoring for firewall restart, set to 0 to disable monitoring
CRON_MINUTE="*/1"
CRON_HOUR="*"

# These should not be changed but they can
IPT="/usr/sbin/iptables"
IPT6="/usr/sbin/ip6tables"
CHAIN="FORCEDNS"
CHAIN_DOT="FORCEDNS_DOT"
CHAIN_BLOCK="FORCEDNS_BLOCK"

# This means that this is a Merlin firmware
if [ -f "/usr/sbin/helper.sh" ]; then
    #shellcheck disable=SC1091
    . /usr/sbin/helper.sh

    DNS_SERVER_=$(am_settings_get jl_fdns_server)
    DNS_SERVER6_=$(am_settings_get jl_fdns_server6)
    PERMIT_MAC_=$(am_settings_get jl_fdns_permit_mac)
    PERMIT_IP_=$(am_settings_get jl_fdns_permit_ip)
    PERMIT_IP6_=$(am_settings_get jl_fdns_permit_ip6)
    REQUIRE_INTERFACE_=$(am_settings_get jl_fdns_require_iface)
    FALLBACK_DNS_SERVER_=$(am_settings_get jl_fdns_fallback)
    FALLBACK_DNS_SERVER6_=$(am_settings_get jl_fdns_fallback6)
    BLOCK_ROUTER_DNS_=$(am_settings_get jjl_fdns_block_router_dnsl_)

    [ -n "$DNS_SERVER_" ] && DNS_SERVER=$DNS_SERVER_
    [ -n "$DNS_SERVER6_" ] && DNS_SERVER6=$DNS_SERVER6_
    [ -n "$PERMIT_MAC_" ] && PERMIT_MAC=$PERMIT_MAC_
    [ -n "$PERMIT_IP_" ] && PERMIT_IP=$PERMIT_IP_
    [ -n "$PERMIT_IP6_" ] && PERMIT_IP6=$PERMIT_IP6_
    [ -n "$REQUIRE_INTERFACE_" ] && REQUIRE_INTERFACE=$REQUIRE_INTERFACE_
    [ -n "$FALLBACK_DNS_SERVER_" ] && FALLBACK_DNS_SERVER=$FALLBACK_DNS_SERVER_
    [ -n "$FALLBACK_DNS_SERVER6_" ] && FALLBACK_DNS_SERVER6=$FALLBACK_DNS_SERVER6_
    [ -n "$BLOCK_ROUTER_DNS_" ] && BLOCK_ROUTER_DNS=$BLOCK_ROUTER_DNS_
fi

readonly SCRIPT_NAME="$(basename "$0" .sh)"
readonly SCRIPT_PATH="$(readlink -f "$0")"
readonly SCRIPT_CONFIG="$(dirname "$0")/$SCRIPT_NAME.conf"
if [ -f "$SCRIPT_CONFIG" ]; then
    #shellcheck disable=SC1090
    . "$SCRIPT_CONFIG"
fi

[ ! -f "$IPT" ] && { echo "Missing iptables binary: $IPT"; exit 1; }

FOR_IPTABLES="$IPT"
ROUTER_IP="$(nvram get lan_ipaddr)"
ROUTER_IP6="$(nvram get ipv6_rtr_addr)"

if [ -z "$DNS_SERVER" ]; then
    DHCP_DNS1="$(nvram get dhcp_dns1_x)"

    if [ -n "$DHCP_DNS1" ]; then
        DNS_SERVER="$DHCP_DNS1"
    else
        DNS_SERVER="$ROUTER_IP"
    fi
fi

if [ "$(nvram get ipv6_service)" != "disabled" ]; then
    [ ! -f "$IPT6" ] && { echo "Missing ip6tables binary: $IPT6"; exit 1; }

    FOR_IPTABLES="$FOR_IPTABLES $IPT6"

    if [ -z "$DNS_SERVER6" ]; then
        DNS_SERVER6="$ROUTER_IP6"
    elif [ "$DNS_SERVER6" = "block" ]; then
        DNS_SERVER6=""
    fi
fi

{ [ "$BLOCK_ROUTER_DNS" = "true" ] || [ "$BLOCK_ROUTER_DNS" = true ]; } && BLOCK_ROUTER_DNS="1" || BLOCK_ROUTER_DNS="0"
{ [ "$USE_WATCHDOG" = "true" ] || [ "$USE_WATCHDOG" = true ]; } && USE_WATCHDOG="1" || USE_WATCHDOG="0"

#shellcheck disable=SC2009
WATCHDOG_PID="$(ps | grep "$SCRIPT_NAME.sh watchdog" | grep -v grep | awk '{print $1}')"

# These "iptables_" functions are based on code from YazFi (https://github.com/jackyaz/YazFi) then modified using code from dnsfiler.c
iptables_chains() {
    for _IPTABLES in $FOR_IPTABLES; do
        case "$1" in
            "add")
                if ! $_IPTABLES -n -L "$CHAIN_DOT" >/dev/null 2>&1; then
                    _FORWARD_START="$($_IPTABLES -nvL FORWARD --line | grep -E "all.*state RELATED,ESTABLISHED" | tail -1 | awk '{print $1}')"
                    _FORWARD_START_PLUS="$((_FORWARD_START+1))"

                    $_IPTABLES -N "$CHAIN_DOT"
                    $_IPTABLES -I FORWARD "$_FORWARD_START_PLUS" -i "$BRIDGE_INTERFACE" -p tcp -m tcp --dport 853 -j "$CHAIN_DOT"
                fi

                if ! $_IPTABLES -t nat -n -L "$CHAIN" >/dev/null 2>&1; then
                    $_IPTABLES -t nat -N "$CHAIN"
                    $_IPTABLES -t nat -I PREROUTING -i "$BRIDGE_INTERFACE" -p tcp -m tcp --dport 53 -j "$CHAIN"
                    $_IPTABLES -t nat -I PREROUTING -i "$BRIDGE_INTERFACE" -p udp -m udp --dport 53 -j "$CHAIN"
                fi

                if [ "$BLOCK_ROUTER_DNS" = "1" ] && ! $_IPTABLES -n -L "$CHAIN_BLOCK" >/dev/null 2>&1; then
                    if [ "$_IPTABLES" = "$IPT6" ]; then
                        _ROUTER_IP="$ROUTER_IP6"
                    else
                        _ROUTER_IP="$ROUTER_IP"
                    fi

                    _INPUT_START="$($_IPTABLES -nvL INPUT --line | grep -E "all.*state INVALID" | tail -1 | awk '{print $1}')"
                    _INPUT_START_PLUS="$((_INPUT_START+1))"

                    $_IPTABLES -N "$CHAIN_BLOCK"
                    $_IPTABLES -I INPUT "$_INPUT_START_PLUS" -i "$BRIDGE_INTERFACE" -p tcp -m tcp --dport 53 -d "$_ROUTER_IP" -j "$CHAIN_BLOCK"
                    $_IPTABLES -I INPUT "$_INPUT_START_PLUS" -i "$BRIDGE_INTERFACE" -p udp -m udp --dport 53 -d "$_ROUTER_IP" -j "$CHAIN_BLOCK"
                fi
            ;;
            "remove")
                if $_IPTABLES -n -L "$CHAIN_DOT" >/dev/null 2>&1; then
                    $_IPTABLES -D FORWARD -i "$BRIDGE_INTERFACE" -p tcp -m tcp --dport 853 -j "$CHAIN_DOT"
                    $_IPTABLES -F "$CHAIN_DOT"
                    $_IPTABLES -X "$CHAIN_DOT"
                fi

                if $_IPTABLES -t nat -n -L "$CHAIN" >/dev/null 2>&1; then
                    $_IPTABLES -t nat -D PREROUTING -i "$BRIDGE_INTERFACE" -p udp -m udp --dport 53 -j "$CHAIN"
                    $_IPTABLES -t nat -D PREROUTING -i "$BRIDGE_INTERFACE" -p tcp -m tcp --dport 53 -j "$CHAIN"
                    $_IPTABLES -t nat -F "$CHAIN"
                    $_IPTABLES -t nat -X "$CHAIN"
                fi

                if $_IPTABLES -n -L "$CHAIN_BLOCK" >/dev/null 2>&1; then
                    if [ "$_IPTABLES" = "$IPT6" ]; then
                        _ROUTER_IP="$ROUTER_IP6"
                    else
                        _ROUTER_IP="$ROUTER_IP"
                    fi

                    $_IPTABLES -D INPUT -i "$BRIDGE_INTERFACE" -p udp -m udp --dport 53 -d "$_ROUTER_IP" -j "$CHAIN_BLOCK"
                    $_IPTABLES -D INPUT -i "$BRIDGE_INTERFACE" -p tcp -m tcp --dport 53 -d "$_ROUTER_IP" -j "$CHAIN_BLOCK"
                    $_IPTABLES -F "$CHAIN_BLOCK"
                    $_IPTABLES -X "$CHAIN_BLOCK"
                fi
            ;;
        esac
    done
}

iptables_rules() {
    _DNS_SERVER="$2"
    _DNS_SERVER6="$3"

    [ -z "$DNS_SERVER" ] && { logger -s -t "Target DNS server is not set"; exit 1; }

    case "$1" in
        "add")
            _ACTION="-A"
        ;;
        "remove")
            _ACTION="-D"
        ;;
    esac


    for _IPTABLES in $FOR_IPTABLES; do
        _BLOCK_ROUTER_DNS="$BLOCK_ROUTER_DNS"

        if [ "$_IPTABLES" = "$IPT6" ]; then
            if [ -z "$DNS_SERVER6" ]; then
                $_IPTABLES -t nat "$_ACTION" "$CHAIN" -j REJECT
                $_IPTABLES "$_ACTION" "$CHAIN_DOT" -j REJECT
                continue
            fi

            _SET_DNS_SERVER="$_DNS_SERVER6"
            _PERMIT_IP="$PERMIT_IP6"
            _ROUTER_IP="$ROUTER_IP6"
        else
            _SET_DNS_SERVER="$_DNS_SERVER"
            _PERMIT_IP="$PERMIT_IP"
            _ROUTER_IP="$ROUTER_IP"
        fi

        [ "$_ROUTER_IP" = "$_SET_DNS_SERVER" ] && _BLOCK_ROUTER_DNS=0

        if [ -n "$PERMIT_MAC" ]; then
            for MAC in $(echo "$PERMIT_MAC" | tr ',' ' '); do
                MAC="$(echo "$MAC" | awk '{$1=$1};1')"

                $_IPTABLES -t nat "$_ACTION" "$CHAIN" -m mac --mac-source "$MAC" -j RETURN
                $_IPTABLES "$_ACTION" "$CHAIN_DOT" -m mac --mac-source "$MAC" -j RETURN
                $_IPTABLES "$_ACTION" "$CHAIN_BLOCK" -m mac --mac-source "$MAC" -j RETURN
            done
        fi

        if [ "${_PERMIT_IP#*"-"}" != "$_PERMIT_IP" ]; then # IP ranges found
            for IP in $(echo "$_PERMIT_IP" | tr ',' ' '); do
                IP="$(echo "$IP" | awk '{$1=$1};1')"

                if [ "${IP#*"-"}" != "$IP" ]; then # IP range entry
                    $_IPTABLES -t nat "$_ACTION" "$CHAIN" -m iprange --src-range "$IP" -j RETURN
                    $_IPTABLES "$_ACTION" "$CHAIN_DOT" -m iprange --src-range "$IP" -j RETURN
                    $_IPTABLES "$_ACTION" "$CHAIN_BLOCK" -m iprange --src-range "$IP" -j RETURN
                else # single IP entry
                    $_IPTABLES -t nat "$_ACTION" "$CHAIN" -s "$IP" -j RETURN
                    $_IPTABLES "$_ACTION" "$CHAIN_DOT" -s "$IP" -j RETURN
                    $_IPTABLES "$_ACTION" "$CHAIN_BLOCK" -s "$IP" -j RETURN
                fi
            done
        else # no IP ranges found, conveniently iptables accept IPs separated by commas
            $_IPTABLES -t nat "$_ACTION" "$CHAIN" -s "$_PERMIT_IP" -j RETURN
            $_IPTABLES "$_ACTION" "$CHAIN_DOT" -s "$_PERMIT_IP" -j RETURN
            $_IPTABLES "$_ACTION" "$CHAIN_BLOCK" -s "$_PERMIT_IP" -j RETURN
        fi

        [ "$_BLOCK_ROUTER_DNS" = "1" ] && $_IPTABLES -t nat "$_ACTION" "$CHAIN" -d "$_ROUTER_IP" -j RETURN

        $_IPTABLES -t nat "$_ACTION" "$CHAIN" -j DNAT --to-destination "$_SET_DNS_SERVER"
        $_IPTABLES "$_ACTION" "$CHAIN_DOT" ! -d "$_SET_DNS_SERVER" -j REJECT

        [ "$_BLOCK_ROUTER_DNS" = "1" ] && $_IPTABLES "$_ACTION" "$CHAIN_BLOCK" -j REJECT
    done
}

setup_rules() {
    _REASON=""
    [ -n "$2" ] && _REASON=" ($2)"

    case "$1" in
        "add")
            iptables_chains remove
            iptables_chains add
            iptables_rules add "${DNS_SERVER}" "${DNS_SERVER6}"

            _DNS_SERVER="$DNS_SERVER"
            [ -n "$DNS_SERVER6" ] && _DNS_SERVER=" $DNS_SERVER6"

            logger -s -t "$SCRIPT_NAME" "Forcing DNS server(s): ${_DNS_SERVER}${_REASON}"
        ;;
        "remove")
            iptables_chains remove

            if [ -n "$FALLBACK_DNS_SERVER" ]; then
                iptables_chains add
                iptables_rules add "${FALLBACK_DNS_SERVER}" "${FALLBACK_DNS_SERVER6}"

                _FALLBACK_DNS_SERVER="$FALLBACK_DNS_SERVER"
                [ -n "$FALLBACK_DNS_SERVER6" ] && _FALLBACK_DNS_SERVER=" $FALLBACK_DNS_SERVER6"

                logger -s -t "$SCRIPT_NAME" "Forcing fallback DNS server(s): ${_FALLBACK_DNS_SERVER}${_REASON}"
            else
                logger -s -t "$SCRIPT_NAME" "DNS server is no longer forced$_REASON"
            fi
        ;;
    esac

    [ -n "$EXECUTE_COMMAND" ] && $EXECUTE_COMMAND "$1"
}

interface_exists() {
    if [ "$(printf "%s" "$1" | tail -c 1)" = "*" ]; then
        for _INTERFACE in /sys/class/net/usb*; do
            [ -d "$_INTERFACE" ] && return 0
        done
    elif [ -d "/sys/class/net/$1" ]; then
        return 0
    fi

    return 1
}

case "$1" in
    "run")
        [ -z "$DNS_SERVER" ] && exit
        RULES_EXIST="$({ $IPT -t nat -C "$CHAIN" -j DNAT --to-destination "$DNS_SERVER" >/dev/null 2>&1 && $IPT -C "$CHAIN_DOT" ! -d "$DNS_SERVER" -j REJECT >/dev/null 2>&1; } && echo 1 || echo 0)"

        if [ -n "$REQUIRE_INTERFACE" ] && ! interface_exists "$REQUIRE_INTERFACE"; then
            [ "$RULES_EXIST" = "1" ] && setup_rules remove "missing interface $REQUIRE_INTERFACE"
        elif [ "$RULES_EXIST" = "0" ]; then
            setup_rules add "missing firewall rules"
        fi
    ;;
    "watchdog")
        set -e

        [ ! -f "$CACHE_FILE" ] && touch "$CACHE_FILE"

        INIT=
        while true; do
            LAST_MATCHING="$(tail /tmp/syslog.log -n 25 | grep 'rc_service.*restart_firewall' | tail -n 1)"

            if [ -n "$LAST_MATCHING" ] && [ "$LAST_MATCHING" != "$(cat "$CACHE_FILE")" ]; then
                echo "$LAST_MATCHING" > "$CACHE_FILE"

                [ -n "$INIT" ] && sh "$SCRIPT_PATH" run
            fi

            [ -z "$INIT" ] && INIT=1

            sleep $WATCHDOG_SLEEP
        done
    ;;
    "run-watchdog")
        cru d "${SCRIPT_NAME}-watchdog"

        #shellcheck disable=SC3020
        [ -z "$WATCHDOG_PID" ] && nohup sh "$SCRIPT_PATH" watchdog 0<&- &>/dev/null &
    ;;
    "start")
        if [ -f "/usr/sbin/helper.sh" ] && [ -z "$REQUIRE_INTERFACE" ] && [ "$BLOCK_ROUTER_DNS" = "0" ]; then
            logger -s -t "$SCRIPT_NAME" "Merlin firmware detected, you should probably use DNS Director instead!"
        fi

        [ -z "$DNS_SERVER" ] && { logger -s -t "$SCRIPT_NAME" "Unable to start - target DNS server is not set"; exit 1; }

        if [ "$USE_WATCHDOG" = "1" ]; then
            [ -z "$WATCHDOG_PID" ] && cru a "${SCRIPT_NAME}-watchdog" "*/1 * * * * $SCRIPT_PATH run-watchdog"
        else
            cru a "$SCRIPT_NAME" "$CRON_MINUTE $CRON_HOUR * * * $SCRIPT_PATH run"
        fi

        { [ -z "$REQUIRE_INTERFACE" ] || interface_exists "$REQUIRE_INTERFACE"; } && setup_rules add
    ;;
    "stop")
        cru d "$SCRIPT_NAME"
        cru d "${SCRIPT_NAME}-watchdog"

        [ -n "$WATCHDOG_PID" ] && kill "$WATCHDOG_PID"

        setup_rules remove
    ;;
    "restart")
        sh "$SCRIPT_PATH" stop
        sh "$SCRIPT_PATH" start
    ;;
    *)
        echo "Usage: $0 run|watchdog|start|stop|restart"
        exit 1
    ;;
esac
