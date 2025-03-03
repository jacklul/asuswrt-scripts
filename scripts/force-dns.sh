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

#jacklul-asuswrt-scripts-update=force-dns.sh
#shellcheck disable=SC2155

readonly script_path="$(readlink -f "$0")"
readonly script_name="$(basename "$script_path" .sh)"
readonly script_dir="$(dirname "$script_path")"
readonly script_config="$script_dir/$script_name.conf"

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
RUN_EVERY_MINUTE=true # verify that the rules are still set (true/false), recommended to keep it enabled even when service-event.sh is available

is_merlin_firmware() { #ISMERLINFIRMWARE_START#
    if [ -f "/usr/sbin/helper.sh" ]; then
        return 0
    fi
    return 1
} #ISMERLINFIRMWARE_END#

is_merlin_firmware && merlin=true

# Disable on Merlin when service-event.sh is available (service-event-end runs it)
if [ -n "$merlin" ] && [ -x "$script_dir/service-event.sh" ]; then
    RUN_EVERY_MINUTE=false
fi

if [ -f "$script_config" ]; then
    #shellcheck disable=SC1090
    . "$script_config"
fi

if [ -z "$RUN_EVERY_MINUTE" ]; then
    [ ! -x "$script_dir/service-event.sh" ] && RUN_EVERY_MINUTE=true
fi

if [ -z "$DNS_SERVER" ]; then
    dhcp_dns1="$(nvram get dhcp_dns1_x)"

    if [ -n "$dhcp_dns1" ]; then
        DNS_SERVER="$dhcp_dns1"
    else
        DNS_SERVER="$router_ip"
    fi
fi

readonly CHAIN_DNAT="FORCEDNS"
readonly CHAIN_DOT="FORCEDNS_DOT"
readonly CHAIN_BLOCK="FORCEDNS_BLOCK"

router_ip="$(nvram get lan_ipaddr)"
router_ip6="$(nvram get ipv6_rtr_addr)"
for_iptables="iptables"

if [ "$(nvram get ipv6_service)" != "disabled" ]; then
    for_iptables="$for_iptables ip6tables"

    if [ -z "$DNS_SERVER6" ]; then
        DNS_SERVER6="$router_ip6"
    elif [ "$DNS_SERVER6" = "block" ]; then
        DNS_SERVER6=""
    fi
fi

lockfile() { #LOCKFILE_START#
    [ -z "$script_name" ] && script_name="$(basename "$0" .sh)"

    _lockfile="/var/lock/script-$script_name.lock"
    _pidfile="/var/run/script-$script_name.pid"
    _fd=100
    _fd_max=200

    if [ -n "$2" ]; then
        _lockfile="/var/lock/script-$script_name-$2.lock"
        _pidfile="/var/run/script-$script_name-$2.lock"
    fi

    [ -n "$3" ] && [ "$3" -eq "$3" ] && _fd="$3" && _fd_max="$3"
    [ -n "$4" ] && [ "$4" -eq "$4" ] && _fd_max="$4"

    [ ! -d /var/lock ] && { mkdir -p /var/lock || exit 1; }
    [ ! -d /var/run ] && { mkdir -p /var/run || exit 1; }

    _lockpid=
    [ -f "$_pidfile" ] && _lockpid="$(cat "$_pidfile")"

    case "$1" in
        "lockwait"|"lockfail"|"lockexit")
            if [ -n "$_lockpid" ] && ! grep -Fq "$script_name" "/proc/$_lockpid/cmdline" 2> /dev/null; then
                _lockpid=
            fi

            case "$1" in
                "lockfail"|"lockexit")
                    if [ -n "$_lockpid" ] && [ -f "/proc/$_lockpid/stat" ]; then
                        [ "$1" = "lockfail" ] && return 1
                        exit 1
                    fi
                ;;
            esac

            while [ -f "/proc/$$/fd/$_fd" ]; do
                _fd=$((_fd+1))

                [ "$_fd" -gt "$_fd_max" ] && { logger -st "$script_name" "Failed to acquire a lock - no free file descriptors available"; exit 1; }
            done

            eval exec "$_fd>$_lockfile"

            case "$1" in
                "lockwait")
                    _lockwait=0
                    while ! flock -nx "$_fd" && { [ -z "$_lockpid" ] || [ -f "/proc/$_lockpid/stat" ] ; }; do #flock -x "$_fd"
                        sleep 1
                        if [ "$_lockwait" -ge 90 ]; then
                            logger -st "$script_name" "Failed to acquire a lock after waiting 90 seconds"
                            exit 1
                        fi
                    done
                ;;
                "lockfail")
                    flock -nx "$_fd" || return 1
                ;;
                "lockexit")
                    flock -nx "$_fd" || exit 1
                ;;
            esac

            echo $$ > "$_pidfile"
            trap 'flock -u $_fd; rm -f "$_lockfile" "$_pidfile"; exit $?' INT TERM EXIT
        ;;
        "unlock")
            flock -u "$_fd"
            rm -f "$_lockfile" "$_pidfile"
            trap - INT TERM EXIT
        ;;
        "check")
            [ -n "$_lockpid" ] && [ -f "/proc/$_lockpid/stat" ] && return 0
            return 1
        ;;
        "kill")
            [ -n "$_lockpid" ] && [ -f "/proc/$_lockpid/stat" ] && kill -9 "$_lockpid" && return 0
            return 1
        ;;
    esac
} #LOCKFILE_END#

interface_exists() {
    if [ "$(printf "%s" "$1" | tail -c 1)" = "*" ]; then
        if ip link show | grep -F ": $1" | grep -Fq "mtu"; then
            return 0
        fi
    elif ip link show | grep -F " $1:" | grep -Fq "mtu"; then
        return 0
    fi

    return 1
}

# These "iptables_" functions are based on code from YazFi (https://github.com/jackyaz/YazFi) then modified using code from dnsfiler.c
iptables_chains() {
    for _iptables in $for_iptables; do
        case "$1" in
            "add")
                if ! $_iptables -nL "$CHAIN_DOT" > /dev/null 2>&1; then
                    _forward_start="$($_iptables -nvL FORWARD --line-numbers | grep -E "all.*state RELATED,ESTABLISHED" | tail -1 | awk '{print $1}')"
                    _forward_start_plus="$((_forward_start+1))"

                    $_iptables -N "$CHAIN_DOT"

                    for _target_interface in $TARGET_INTERFACES; do
                        $_iptables -I FORWARD "$_forward_start_plus" -i "$_target_interface" -p tcp -m tcp --dport 853 -j "$CHAIN_DOT"
                        _forward_start_plus="$((_forward_start_plus+1))"
                    done
                fi

                if ! $_iptables -t nat -nL "$CHAIN_DNAT" > /dev/null 2>&1; then
                    _prerouting_start="$($_iptables -t nat -nvL PREROUTING --line-numbers | grep -E "VSERVER" | tail -1 | awk '{print $1}')"
                    _prerouting_start_plus="$((_prerouting_start+1))"

                    $_iptables -t nat -N "$CHAIN_DNAT"

                    for _target_interface in $TARGET_INTERFACES; do
                        $_iptables -t nat -I PREROUTING "$_prerouting_start_plus" -i "$_target_interface" -p tcp -m tcp --dport 53 -j "$CHAIN_DNAT"
                        $_iptables -t nat -I PREROUTING "$_prerouting_start_plus" -i "$_target_interface" -p udp -m udp --dport 53 -j "$CHAIN_DNAT"
                        _prerouting_start_plus="$((_prerouting_start_plus+2))"
                    done
                fi

                if [ "$BLOCK_ROUTER_DNS" = true ] && ! $_iptables -nL "$CHAIN_BLOCK" > /dev/null 2>&1; then
                    if [ "$_iptables" = "ip6tables" ]; then
                        _router_ip="$router_ip6"
                    else
                        _router_ip="$router_ip"
                    fi

                    _input_start="$($_iptables -nvL INPUT --line-numbers | grep -E "all.*state INVALID" | tail -1 | awk '{print $1}')"
                    _input_start_plus="$((_input_start+1))"

                    $_iptables -N "$CHAIN_BLOCK"

                    for _target_interface in $TARGET_INTERFACES; do
                        $_iptables -I INPUT "$_input_start_plus" -i "$_target_interface" -p tcp -m tcp --dport 53 -d "$_router_ip" -j "$CHAIN_BLOCK"
                        $_iptables -I INPUT "$_input_start_plus" -i "$_target_interface" -p udp -m udp --dport 53 -d "$_router_ip" -j "$CHAIN_BLOCK"
                        _input_start_plus="$((_input_start_plus+2))"
                    done
                fi
            ;;
            "remove")
                if $_iptables -nL "$CHAIN_DOT" > /dev/null 2>&1; then
                    for _target_interface in $TARGET_INTERFACES; do
                        $_iptables -D FORWARD -i "$_target_interface" -p tcp -m tcp --dport 853 -j "$CHAIN_DOT"
                    done

                    $_iptables -F "$CHAIN_DOT"
                    $_iptables -X "$CHAIN_DOT"
                fi

                if $_iptables -t nat -nL "$CHAIN_DNAT" > /dev/null 2>&1; then
                    for _target_interface in $TARGET_INTERFACES; do
                        $_iptables -t nat -D PREROUTING -i "$_target_interface" -p udp -m udp --dport 53 -j "$CHAIN_DNAT"
                        $_iptables -t nat -D PREROUTING -i "$_target_interface" -p tcp -m tcp --dport 53 -j "$CHAIN_DNAT"
                    done

                    $_iptables -t nat -F "$CHAIN_DNAT"
                    $_iptables -t nat -X "$CHAIN_DNAT"
                fi

                if $_iptables -nL "$CHAIN_BLOCK" > /dev/null 2>&1; then
                    if [ "$_iptables" = "ip6tables" ]; then
                        _router_ip="$router_ip6"
                    else
                        _router_ip="$router_ip"
                    fi

                    for _target_interface in $TARGET_INTERFACES; do
                        $_iptables -D INPUT -i "$_target_interface" -p udp -m udp --dport 53 -d "$_router_ip" -j "$CHAIN_BLOCK"
                        $_iptables -D INPUT -i "$_target_interface" -p tcp -m tcp --dport 53 -d "$_router_ip" -j "$CHAIN_BLOCK"
                    done

                    $_iptables -F "$CHAIN_BLOCK"
                    $_iptables -X "$CHAIN_BLOCK"
                fi
            ;;
        esac
    done
}

iptables_rules() {
    _dns_server="$2"
    _dns_server6="$3"

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
                $_iptables -t nat "$_action" "$CHAIN_DNAT" -j REJECT
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

        if [ -n "$PERMIT_MAC" ]; then
            for _mac in $(echo "$PERMIT_MAC" | tr ',' ' '); do
                _mac="$(echo "$_mac" | awk '{$1=$1};1')"

                $_iptables -t nat "$_action" "$CHAIN_DNAT" -m mac --mac-source "$_mac" -j RETURN
                $_iptables "$_action" "$CHAIN_DOT" -m mac --mac-source "$_mac" -j RETURN
                [ "$_block_router_dns" = true ] && $_iptables "$_action" "$CHAIN_BLOCK" -m mac --mac-source "$_mac" -j RETURN
            done
        fi

        if [ "${_permit_ip#*"-"}" != "$_permit_ip" ]; then # IP ranges found
            for _ip in $(echo "$_permit_ip" | tr ',' ' '); do
                _ip="$(echo "$_ip" | awk '{$1=$1};1')"

                if [ "${IP#*"-"}" != "$_ip" ]; then # IP range entry
                    $_iptables -t nat "$_action" "$CHAIN_DNAT" -m iprange --src-range "$_ip" -j RETURN
                    $_iptables "$_action" "$CHAIN_DOT" -m iprange --src-range "$_ip" -j RETURN
                    [ "$_block_router_dns" = true ] && $_iptables "$_action" "$CHAIN_BLOCK" -m iprange --src-range "$_ip" -j RETURN
                else # single IP entry
                    $_iptables -t nat "$_action" "$CHAIN_DNAT" -s "$_ip" -j RETURN
                    $_iptables "$_action" "$CHAIN_DOT" -s "$_ip" -j RETURN
                    [ "$_block_router_dns" = true ] && $_iptables "$_action" "$CHAIN_BLOCK" -s "$_ip" -j RETURN
                fi
            done
        else # no IP ranges found, conveniently iptables accept IPs separated by commas
            $_iptables -t nat "$_action" "$CHAIN_DNAT" -s "$_permit_ip" -j RETURN
            $_iptables "$_action" "$CHAIN_DOT" -s "$_permit_ip" -j RETURN
            [ "$_block_router_dns" = true ] && $_iptables "$_action" "$CHAIN_BLOCK" -s "$_permit_ip" -j RETURN
        fi

        [ "$_block_router_dns" = true ] && $_iptables -t nat "$_action" "$CHAIN_DNAT" -d "$_router_ip" -j RETURN

        $_iptables -t nat "$_action" "$CHAIN_DNAT" -j DNAT --to-destination "$_set_dns_server"
        $_iptables "$_action" "$CHAIN_DOT" ! -d "$_set_dns_server" -j REJECT

        [ "$_block_router_dns" = true ] && $_iptables "$_action" "$CHAIN_BLOCK" -j REJECT
    done
}

rules_exist() {
    if iptables -t nat -nL "$CHAIN_DNAT" > /dev/null 2>&1 && iptables -nL "$CHAIN_DOT" > /dev/null 2>&1; then
        if iptables -t nat -C "$CHAIN_DNAT" -j DNAT --to-destination "$1" > /dev/null 2>&1; then
            return 0
        fi
    fi

    return 1
}

firewall_rules() {
    [ -z "$DNS_SERVER" ] && { logger -st "$script_name" "Target DNS server is not set"; exit 1; }
    [ -z "$TARGET_INTERFACES" ] && { logger -st "$script_name" "Target interfaces are not set"; exit 1; }

    lockfile lockwait

    _rules_modified=0
    case "$1" in
        "add")
            if ! rules_exist "$DNS_SERVER"; then
                _rules_modified=1

                iptables_chains remove

                if [ "$VERIFY_DNS" = false ] || nslookup "$VERIFY_DNS_DOMAIN" "$DNS_SERVER" >/dev/null 2>&1; then
                    iptables_chains add
                    iptables_rules add "$DNS_SERVER" "$DNS_SERVER6"

                    _dns_server="$DNS_SERVER"
                    [ -n "$DNS_SERVER6" ] && _dns_server=" $DNS_SERVER6"

                    logger -st "$script_name" "Forcing DNS server(s): $_dns_server"
                fi
            fi
        ;;
        "remove")
            if [ -n "$FALLBACK_DNS_SERVER" ]; then
                if ! rules_exist "$FALLBACK_DNS_SERVER"; then
                    _rules_modified=-1

                    iptables_chains remove

                    if [ "$VERIFY_DNS_FALLBACK" = false ] || nslookup "$VERIFY_DNS_DOMAIN" "$FALLBACK_DNS_SERVER" >/dev/null 2>&1; then
                        iptables_chains add
                        iptables_rules add "$FALLBACK_DNS_SERVER" "$FALLBACK_DNS_SERVER6"

                        _fallback_dns_server="$FALLBACK_DNS_SERVER"
                        [ -n "$FALLBACK_DNS_SERVER6" ] && _fallback_dns_server=" $FALLBACK_DNS_SERVER6"

                        logger -st "$script_name" "Forcing fallback DNS server(s): $_fallback_dns_server"
                    fi
                fi
            else
                if rules_exist "$DNS_SERVER" || rules_exist "$FALLBACK_DNS_SERVER"; then
                    _rules_modified=-1

                    iptables_chains remove
                fi
            fi
        ;;
    esac

    [ -n "$EXECUTE_COMMAND" ] && [ "$_rules_modified" -ne 0 ] && $EXECUTE_COMMAND "$1"

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
            logger -st "$script_name" "Fallback DNS server(s) not set!"
        fi
    ;;
    "start")
        [ -n "$merlin" ] && logger -st "$script_name" "Asuswrt-Merlin firmware detected, you should probably use DNS Director instead!"

        [ -z "$DNS_SERVER" ] && { logger -st "$script_name" "Unable to start - target DNS server is not set"; exit 1; }

        if [ "$RUN_EVERY_MINUTE" = true ]; then
            if [ -x "$script_dir/cron-queue.sh" ]; then
                sh "$script_dir/cron-queue.sh" add "$script_name" "$script_path run"
            else
                cru a "$script_name" "*/1 * * * * $script_path run"
            fi
        fi

        { [ -z "$REQUIRE_INTERFACE" ] || interface_exists "$REQUIRE_INTERFACE" ; } && firewall_rules add
    ;;
    "stop")
        [ -x "$script_dir/cron-queue.sh" ] && sh "$script_dir/cron-queue.sh" remove "$script_name"
        cru d "$script_name"

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
