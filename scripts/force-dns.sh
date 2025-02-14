#!/bin/sh
# Made by Jack'lul <jacklul.github.io>
#
# Forces LAN to use specified DNS server
#
# Implements DNS Director feature from Asuswrt-Merlin:
#  https://github.com/RMerl/asuswrt-merlin.ng/wiki/DNS-Director
#
# Can set rules depending on whenever specific interface is available and define a fallback DNS server when it is not.
# Can also prevent clients from querying router's DNS server while the rules are applied.
#
# If you need per-device DNS settings then these will help you write your own script (which you can execute via EXECUTE_COMMAND variable):
#  iptables -I "FORCEDNS" -m mac --mac-source "d9:32:cb:d0:fe:fe" -j DNAT --to-destination "1.1.1.1"
#  iptables -I "FORCEDNS_DOT" -m mac --mac-source "d9:32:cb:d0:fe:fe" ! -d "1.1.1.1" -j REJECT
#

#jacklul-asuswrt-scripts-update
#shellcheck disable=SC2155

readonly SCRIPT_PATH="$(readlink -f "$0")"
readonly SCRIPT_NAME="$(basename "$SCRIPT_PATH" .sh)"
readonly SCRIPT_DIR="$(dirname "$SCRIPT_PATH")"
readonly SCRIPT_CONFIG="$SCRIPT_DIR/$SCRIPT_NAME.conf"
readonly SCRIPT_TAG="$(basename "$SCRIPT_PATH")"

DNS_SERVER="" # when left empty will use DNS server set in DHCP DNS1 (or router's address if that field is empty)
DNS_SERVER6="" # same as DNS_SERVER but for IPv6, when left empty will use router's address, set to "block" to block IPv6 DNS traffic
PERMIT_MAC="" # space/comma separated allowed MAC addresses to bypass forced DNS
PERMIT_IP="" # space/comma separated allowed v4 IPs to bypass forced DNS, ranges supported
PERMIT_IP6="" # space/comma separated allowed v6 IPs to bypass forced DNS, ranges supported
TARGET_INTERFACES="br+" # the target interface(s) to set rules for, separated by spaces
REQUIRE_INTERFACE="" # rules will be removed if this interface is not up, wildcards accepted, set this to "usb*" when using usb-network script and Pi-hole on USB connected Raspberry Pi
FALLBACK_DNS_SERVER="" # set to this DNS server when interface defined in REQUIRE_INTERFACE does not exist
FALLBACK_DNS_SERVER6="" # set to this DNS server (IPv6) when interface defined in REQUIRE_INTERFACE does not exist
EXECUTE_COMMAND="" # execute a command after firewall rules are applied or removed (receives arguments: $1 = action)
BLOCK_ROUTER_DNS=false # block access to router's DNS server while the rules are set, best used with REQUIRE_INTERFACE and "Advertise router as DNS" option
VERIFY_DNS=false # verify that the DNS server is working before applying
VERIFY_DNS_FALLBACK=false # verify that the DNS server is working before applying (fallback only)
VERIFY_DNS_DOMAIN=asus.com # domain used when checking if DNS server is working

if [ -f "$SCRIPT_CONFIG" ]; then
    #shellcheck disable=SC1090
    . "$SCRIPT_CONFIG"
fi

CHAIN_DNAT="FORCEDNS"
CHAIN_DOT="FORCEDNS_DOT"
CHAIN_BLOCK="FORCEDNS_BLOCK"
FOR_IPTABLES="iptables"
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
    FOR_IPTABLES="$FOR_IPTABLES ip6tables"

    if [ -z "$DNS_SERVER6" ]; then
        DNS_SERVER6="$ROUTER_IP6"
    elif [ "$DNS_SERVER6" = "block" ]; then
        DNS_SERVER6=""
    fi
fi

lockfile() { #LOCKFILE_START#
    _LOCKFILE="/var/lock/script-$SCRIPT_NAME.lock"
    _PIDFILE="/var/run/script-$SCRIPT_NAME.pid"
    _FD=100
    _FD_MAX=200

    if [ -n "$2" ]; then
        _LOCKFILE="/var/lock/script-$SCRIPT_NAME-$2.lock"
        _PIDFILE="/var/run/script-$SCRIPT_NAME-$2.lock"
    fi

    [ -n "$3" ] && [ "$3" -eq "$3" ] && _FD="$3" && _FD_MAX="$3"
    [ -n "$4" ] && [ "$4" -eq "$4" ] && _FD_MAX="$4"

    [ ! -d /var/lock ] && mkdir -p /var/lock
    [ ! -d /var/run ] && mkdir -p /var/run

    _LOCKPID=
    [ -f "$_PIDFILE" ] && _LOCKPID="$(cat "$_PIDFILE")"

    case "$1" in
        "lockwait"|"lockfail"|"lockexit")
            while [ -f "/proc/$$/fd/$_FD" ]; do
                #echo "File descriptor $_FD is already in use ($(readlink -f "/proc/$$/fd/$_FD"))"
                _FD=$((_FD+1))

                [ "$_FD" -gt "$_FD_MAX" ] && { echo "Failed to find available file descriptor"; exit 1; }
            done

            eval exec "$_FD>$_LOCKFILE"

            case "$1" in
                "lockwait")
                    flock -x "$_FD"
                ;;
                "lockfail")
                    flock -nx "$_FD" || return 1
                ;;
                "lockexit")
                    flock -nx "$_FD" || exit 1
                ;;
            esac

            echo $$ > "$_PIDFILE"
            trap 'flock -u $_FD; rm -f "$_LOCKFILE" "$_PIDFILE"; exit $?' INT TERM EXIT
        ;;
        "unlock")
            flock -u "$_FD"
            rm -f "$_LOCKFILE" "$_PIDFILE"
            trap - INT TERM EXIT
        ;;
        "check")
            [ -n "$_LOCKPID" ] && [ -f "/proc/$_LOCKPID/stat" ] && return 0
            return 1
        ;;
        "kill")
            [ -n "$_LOCKPID" ] && [ -f "/proc/$_LOCKPID/stat" ] && kill -9 "$_LOCKPID" && return 0
            return 1
        ;;
    esac
} #LOCKFILE_END#

# These "iptables_" functions are based on code from YazFi (https://github.com/jackyaz/YazFi) then modified using code from dnsfiler.c
iptables_chains() {
    for _IPTABLES in $FOR_IPTABLES; do
        case "$1" in
            "add")
                if ! $_IPTABLES -nL "$CHAIN_DOT" > /dev/null 2>&1; then
                    _FORWARD_START="$($_IPTABLES -nvL FORWARD --line-numbers | grep -E "all.*state RELATED,ESTABLISHED" | tail -1 | awk '{print $1}')"
                    _FORWARD_START_PLUS="$((_FORWARD_START+1))"

                    $_IPTABLES -N "$CHAIN_DOT"

                    for _TARGET_INTERFACE in $TARGET_INTERFACES; do
                        $_IPTABLES -I FORWARD "$_FORWARD_START_PLUS" -i "$_TARGET_INTERFACE" -p tcp -m tcp --dport 853 -j "$CHAIN_DOT"
                        _FORWARD_START_PLUS="$((_FORWARD_START_PLUS+1))"
                    done
                fi

                if ! $_IPTABLES -t nat -nL "$CHAIN_DNAT" > /dev/null 2>&1; then
                    _PREROUTING_START="$($_IPTABLES -t nat -nvL PREROUTING --line-numbers | grep -E "VSERVER" | tail -1 | awk '{print $1}')"
                    _PREROUTING_START_PLUS="$((_PREROUTING_START+1))"

                    $_IPTABLES -t nat -N "$CHAIN_DNAT"

                    for _TARGET_INTERFACE in $TARGET_INTERFACES; do
                        $_IPTABLES -t nat -I PREROUTING "$_PREROUTING_START_PLUS" -i "$_TARGET_INTERFACE" -p tcp -m tcp --dport 53 -j "$CHAIN_DNAT"
                        $_IPTABLES -t nat -I PREROUTING "$_PREROUTING_START_PLUS" -i "$_TARGET_INTERFACE" -p udp -m udp --dport 53 -j "$CHAIN_DNAT"
                        _PREROUTING_START_PLUS="$((_PREROUTING_START_PLUS+2))"
                    done
                fi

                if [ "$BLOCK_ROUTER_DNS" = true ] && ! $_IPTABLES -nL "$CHAIN_BLOCK" > /dev/null 2>&1; then
                    if [ "$_IPTABLES" = "ip6tables" ]; then
                        _ROUTER_IP="$ROUTER_IP6"
                    else
                        _ROUTER_IP="$ROUTER_IP"
                    fi

                    _INPUT_START="$($_IPTABLES -nvL INPUT --line-numbers | grep -E "all.*state INVALID" | tail -1 | awk '{print $1}')"
                    _INPUT_START_PLUS="$((_INPUT_START+1))"

                    $_IPTABLES -N "$CHAIN_BLOCK"

                    for _TARGET_INTERFACE in $TARGET_INTERFACES; do
                        $_IPTABLES -I INPUT "$_INPUT_START_PLUS" -i "$_TARGET_INTERFACE" -p tcp -m tcp --dport 53 -d "$_ROUTER_IP" -j "$CHAIN_BLOCK"
                        $_IPTABLES -I INPUT "$_INPUT_START_PLUS" -i "$_TARGET_INTERFACE" -p udp -m udp --dport 53 -d "$_ROUTER_IP" -j "$CHAIN_BLOCK"
                        _INPUT_START_PLUS="$((_INPUT_START_PLUS+2))"
                    done
                fi
            ;;
            "remove")
                if $_IPTABLES -nL "$CHAIN_DOT" > /dev/null 2>&1; then
                    for _TARGET_INTERFACE in $TARGET_INTERFACES; do
                        $_IPTABLES -D FORWARD -i "$_TARGET_INTERFACE" -p tcp -m tcp --dport 853 -j "$CHAIN_DOT"
                    done

                    $_IPTABLES -F "$CHAIN_DOT"
                    $_IPTABLES -X "$CHAIN_DOT"
                fi

                if $_IPTABLES -t nat -nL "$CHAIN_DNAT" > /dev/null 2>&1; then
                    for _TARGET_INTERFACE in $TARGET_INTERFACES; do
                        $_IPTABLES -t nat -D PREROUTING -i "$_TARGET_INTERFACE" -p udp -m udp --dport 53 -j "$CHAIN_DNAT"
                        $_IPTABLES -t nat -D PREROUTING -i "$_TARGET_INTERFACE" -p tcp -m tcp --dport 53 -j "$CHAIN_DNAT"
                    done

                    $_IPTABLES -t nat -F "$CHAIN_DNAT"
                    $_IPTABLES -t nat -X "$CHAIN_DNAT"
                fi

                if $_IPTABLES -nL "$CHAIN_BLOCK" > /dev/null 2>&1; then
                    if [ "$_IPTABLES" = "ip6tables" ]; then
                        _ROUTER_IP="$ROUTER_IP6"
                    else
                        _ROUTER_IP="$ROUTER_IP"
                    fi

                    for _TARGET_INTERFACE in $TARGET_INTERFACES; do
                        $_IPTABLES -D INPUT -i "$_TARGET_INTERFACE" -p udp -m udp --dport 53 -d "$_ROUTER_IP" -j "$CHAIN_BLOCK"
                        $_IPTABLES -D INPUT -i "$_TARGET_INTERFACE" -p tcp -m tcp --dport 53 -d "$_ROUTER_IP" -j "$CHAIN_BLOCK"
                    done

                    $_IPTABLES -F "$CHAIN_BLOCK"
                    $_IPTABLES -X "$CHAIN_BLOCK"
                fi
            ;;
        esac
    done
}

iptables_rules() {
    [ -z "$DNS_SERVER" ] && { logger -st "$SCRIPT_TAG" "Target DNS server is not set"; exit 1; }

    _DNS_SERVER="$2"
    _DNS_SERVER6="$3"

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

        if [ "$_IPTABLES" = "ip6tables" ]; then
            if [ -z "$DNS_SERVER6" ]; then
                $_IPTABLES -t nat "$_ACTION" "$CHAIN_DNAT" -j REJECT
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

        [ "$_ROUTER_IP" = "$_SET_DNS_SERVER" ] && _BLOCK_ROUTER_DNS=false

        if [ -n "$PERMIT_MAC" ]; then
            for MAC in $(echo "$PERMIT_MAC" | tr ',' ' '); do
                MAC="$(echo "$MAC" | awk '{$1=$1};1')"

                $_IPTABLES -t nat "$_ACTION" "$CHAIN_DNAT" -m mac --mac-source "$MAC" -j RETURN
                $_IPTABLES "$_ACTION" "$CHAIN_DOT" -m mac --mac-source "$MAC" -j RETURN
                [ "$_BLOCK_ROUTER_DNS" = true ] && $_IPTABLES "$_ACTION" "$CHAIN_BLOCK" -m mac --mac-source "$MAC" -j RETURN
            done
        fi

        if [ "${_PERMIT_IP#*"-"}" != "$_PERMIT_IP" ]; then # IP ranges found
            for IP in $(echo "$_PERMIT_IP" | tr ',' ' '); do
                IP="$(echo "$IP" | awk '{$1=$1};1')"

                if [ "${IP#*"-"}" != "$IP" ]; then # IP range entry
                    $_IPTABLES -t nat "$_ACTION" "$CHAIN_DNAT" -m iprange --src-range "$IP" -j RETURN
                    $_IPTABLES "$_ACTION" "$CHAIN_DOT" -m iprange --src-range "$IP" -j RETURN
                    [ "$_BLOCK_ROUTER_DNS" = true ] && $_IPTABLES "$_ACTION" "$CHAIN_BLOCK" -m iprange --src-range "$IP" -j RETURN
                else # single IP entry
                    $_IPTABLES -t nat "$_ACTION" "$CHAIN_DNAT" -s "$IP" -j RETURN
                    $_IPTABLES "$_ACTION" "$CHAIN_DOT" -s "$IP" -j RETURN
                    [ "$_BLOCK_ROUTER_DNS" = true ] && $_IPTABLES "$_ACTION" "$CHAIN_BLOCK" -s "$IP" -j RETURN
                fi
            done
        else # no IP ranges found, conveniently iptables accept IPs separated by commas
            $_IPTABLES -t nat "$_ACTION" "$CHAIN_DNAT" -s "$_PERMIT_IP" -j RETURN
            $_IPTABLES "$_ACTION" "$CHAIN_DOT" -s "$_PERMIT_IP" -j RETURN
            [ "$_BLOCK_ROUTER_DNS" = true ] && $_IPTABLES "$_ACTION" "$CHAIN_BLOCK" -s "$_PERMIT_IP" -j RETURN
        fi

        [ "$_BLOCK_ROUTER_DNS" = true ] && $_IPTABLES -t nat "$_ACTION" "$CHAIN_DNAT" -d "$_ROUTER_IP" -j RETURN

        $_IPTABLES -t nat "$_ACTION" "$CHAIN_DNAT" -j DNAT --to-destination "$_SET_DNS_SERVER"
        $_IPTABLES "$_ACTION" "$CHAIN_DOT" ! -d "$_SET_DNS_SERVER" -j REJECT

        [ "$_BLOCK_ROUTER_DNS" = true ] && $_IPTABLES "$_ACTION" "$CHAIN_BLOCK" -j REJECT
    done
}

firewall_rules() {
    [ -z "$TARGET_INTERFACES" ] && { logger -st "$SCRIPT_TAG" "Target interfaces are not set"; exit 1; }

    lockfile lockwait

    case "$1" in
        "add")
            if ! rules_exist "$DNS_SERVER"; then
                iptables_chains remove

                if [ "$VERIFY_DNS" = false ] || nslookup "$VERIFY_DNS_DOMAIN" "$DNS_SERVER" >/dev/null 2>&1; then
                    iptables_chains add
                    iptables_rules add "${DNS_SERVER}" "${DNS_SERVER6}"

                    _DNS_SERVER="$DNS_SERVER"
                    [ -n "$DNS_SERVER6" ] && _DNS_SERVER=" $DNS_SERVER6"

                    logger -st "$SCRIPT_TAG" "Forcing DNS server(s): ${_DNS_SERVER}"
                fi
            fi
        ;;
        "remove")
            if [ -n "$FALLBACK_DNS_SERVER" ]; then
                if ! rules_exist "$FALLBACK_DNS_SERVER"; then
                    iptables_chains remove

                    if [ "$VERIFY_DNS_FALLBACK" = false ] || nslookup "$VERIFY_DNS_DOMAIN" "$FALLBACK_DNS_SERVER" >/dev/null 2>&1; then
                        iptables_chains add
                        iptables_rules add "${FALLBACK_DNS_SERVER}" "${FALLBACK_DNS_SERVER6}"

                        _FALLBACK_DNS_SERVER="$FALLBACK_DNS_SERVER"
                        [ -n "$FALLBACK_DNS_SERVER6" ] && _FALLBACK_DNS_SERVER=" $FALLBACK_DNS_SERVER6"

                        logger -st "$SCRIPT_TAG" "Forcing fallback DNS server(s): ${_FALLBACK_DNS_SERVER}"
                    fi
                fi
            else
                iptables_chains remove
            fi
        ;;
    esac

    [ -n "$EXECUTE_COMMAND" ] && $EXECUTE_COMMAND "$1"

    lockfile unlock
}

interface_exists() {
    if [ "$(printf "%s" "$1" | tail -c 1)" = "*" ]; then
        _INTERFACE_GLOB="$(printf "%s" "$1" | head -c -1)"

        if ip link show | grep ": $1" | grep -q "mtu"; then
            return 0
        fi
    elif ip link show | grep " $1:" | grep -q "mtu"; then
        return 0
    fi

    return 1
}

rules_exist() {
    if iptables -t nat -nL "$CHAIN_DNAT" > /dev/null 2>&1 && iptables -nL "$CHAIN_DOT" > /dev/null 2>&1; then
        if iptables -t nat -C "$CHAIN_DNAT" -j DNAT --to-destination "$1" > /dev/null 2>&1; then
            return 0
        fi
    fi

    return 1
}

case "$1" in
    "run")
        [ -z "$DNS_SERVER" ] && exit

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
            logger -st "$SCRIPT_TAG" "Fallback DNS server(s) not set!"
        fi
    ;;
    "start")
        [ -f "/usr/sbin/helper.sh" ] && logger -st "$SCRIPT_TAG" "Asuswrt-Merlin firmware detected, you should probably use DNS Director instead!"

        [ -z "$DNS_SERVER" ] && { logger -st "$SCRIPT_TAG" "Unable to start - target DNS server is not set"; exit 1; }

        if [ -x "$SCRIPT_DIR/cron-queue.sh" ]; then
            sh "$SCRIPT_DIR/cron-queue.sh" add "$SCRIPT_NAME" "$SCRIPT_PATH run"
        else
            cru a "$SCRIPT_NAME" "*/1 * * * * $SCRIPT_PATH run"
        fi

        { [ -z "$REQUIRE_INTERFACE" ] || interface_exists "$REQUIRE_INTERFACE"; } && firewall_rules add
    ;;
    "stop")
        [ -x "$SCRIPT_DIR/cron-queue.sh" ] && sh "$SCRIPT_DIR/cron-queue.sh" remove "$SCRIPT_NAME"
        cru d "$SCRIPT_NAME"

        FALLBACK_DNS_SERVER="" # prevent changing to fallback instead of removing everything...
        firewall_rules remove
    ;;
    "restart")
        sh "$SCRIPT_PATH" stop
        sh "$SCRIPT_PATH" start
    ;;
    *)
        echo "Usage: $0 run|start|stop|restart|fallback"
        exit 1
    ;;
esac
