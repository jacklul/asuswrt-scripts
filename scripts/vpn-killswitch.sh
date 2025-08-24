#!/bin/sh
# Made by Jack'lul <jacklul.github.io>
#
# Prevent access to internet without VPN connection
#
# Based on:
#  https://github.com/ZebMcKayhan/WireguardManager/blob/main/wg_manager.sh
#

#jacklul-asuswrt-scripts-update=vpn-killswitch.sh
#shellcheck disable=SC2155

readonly script_path="$(readlink -f "$0")"
readonly script_name="$(basename "$script_path" .sh)"
readonly script_dir="$(dirname "$script_path")"
readonly script_config="$script_dir/$script_name.conf"

BRIDGE_INTERFACES="br+" # the bridge interface to set rules for, by default affects all "br" interfaces (which also includes guest network bridge), separated by spaces
EXECUTE_COMMAND="" # execute a command after firewall rules are applied or removed (receives arguments: $1 = action)
RUN_EVERY_MINUTE=true # verify that the rules are still set (true/false), recommended to keep it enabled even when service-event.sh is available

is_merlin_firmware() { #ISMERLINFIRMWARE_START#
    if [ -f "/usr/sbin/helper.sh" ]; then
        return 0
    fi
    return 1
} #ISMERLINFIRMWARE_END#

# Disable on Merlin when service-event.sh is available (service-event-end runs it)
if is_merlin_firmware && [ -x "$script_dir/service-event.sh" ]; then
    RUN_EVERY_MINUTE=false
fi

if [ -f "$script_config" ]; then
    #shellcheck disable=SC1090
    . "$script_config"
fi

if [ -z "$RUN_EVERY_MINUTE" ]; then
    [ ! -x "$script_dir/service-event.sh" ] && RUN_EVERY_MINUTE=true
fi

readonly CHAIN="VPN_KILLSWITCH"

for_iptables="iptables"
[ "$(nvram get ipv6_service)" != "disabled" ] && for_iptables="$for_iptables ip6tables"

lockfile() { #LOCKFILE_START#
    [ -z "$script_name" ] && script_name="$(basename "$0" .sh)"

    _lockfile="/var/lock/script-$script_name.lock"
    _pidfile="/var/run/script-$script_name.pid"
    _fd_min=100
    _fd_max=200

    if [ -n "$2" ]; then
        _lockfile="/var/lock/script-$script_name-$2.lock"
        _pidfile="/var/run/script-$script_name-$2.lock"
    fi

    [ -n "$3" ] && _fd_min="$3" && _fd_max="$3"
    [ -n "$4" ] && _fd_max="$4"

    [ ! -d /var/lock ] && { mkdir -p /var/lock || exit 1; }
    [ ! -d /var/run ] && { mkdir -p /var/run || exit 1; }

    _lockpid=
    [ -f "$_pidfile" ] && _lockpid="$(cat "$_pidfile")"

    case "$1" in
        "lockwait"|"lockfail"|"lockexit")
            for _fd_test in "/proc/$$/fd"/*; do
                if [ "$(readlink -f "$_fd_test")" = "$_lockfile" ]; then
                    logger -st "$script_name" "File descriptor ($(basename "$_fd_test")) is already open for the same lockfile ($_lockfile)"
                    exit 1
                fi
            done

            _fd=$(lockfile_fd "$_fd_min" "$_fd_max")
            eval exec "$_fd>$_lockfile"

            case "$1" in
                "lockwait")
                    _lockwait=0
                    while ! flock -nx "$_fd"; do
                        eval exec "$_fd>&-"
                        _lockwait=$((_lockwait+1))

                        if [ "$_lockwait" -ge 60 ]; then
                            logger -st "$script_name" "Failed to acquire a lock after 60 seconds ($_lockfile)"
                            exit 1
                        fi

                        sleep 1
                        _fd=$(lockfile_fd "$_fd_min" "$_fd_max")
                        eval exec "$_fd>$_lockfile"
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
            chmod 644 "$_pidfile"
            trap 'flock -u $_fd; rm -f "$_lockfile" "$_pidfile"; exit $?' INT TERM EXIT
        ;;
        "unlock")
            flock -u "$_fd"
            eval exec "$_fd>&-"
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
}

lockfile_fd() {
    _lfd_min=$1
    _lfd_max=$2

    while [ -f "/proc/$$/fd/$_lfd_min" ]; do
        _lfd_min=$((_lfd_min+1))
        [ "$_lfd_min" -gt "$_lfd_max" ] && { logger -st "$script_name" "Error: No free file descriptors available"; exit 1; }
    done

    echo "$_lfd_min"
} #LOCKFILE_END#

get_wan_interface() {
    _interface="$(nvram get wan0_ifname)"

    if [ "$(nvram get wan0_gw_ifname)" != "$_interface" ]; then
        _interface=$(nvram get wan0_gw_ifname)
    fi

    if [ -n "$(nvram get wan0_pppoe_ifname)" ]; then
        _interface="$(nvram get wan0_pppoe_ifname)"
    fi

    [ -z "$_interface" ] && { logger -st "$script_name" "Error: Couldn't get WAN interface name"; exit 1; }

    echo "$_interface"
}

verify_bridge_interfaces() {
    if echo "$BRIDGE_INTERFACES" | grep -Fq "br+"; then
        BRIDGE_INTERFACES="br+" # sanity set, just in case one sets "br0 br+ br23"
    else
        for _bridge_interface in $BRIDGE_INTERFACES; do
            if ! ip link show | grep -F ": $_bridge_interface" | grep -Fq "mtu"; then
                logger -st "$script_name" "Couldn't find matching bridge interface for $_bridge_interface"
                exit 1
            fi
        done
    fi
}

firewall_rules() {
    [ -z "$BRIDGE_INTERFACES" ] && { logger -st "$script_name" "Error: Bridge interfaces are not set"; exit 1; }

    lockfile lockwait

    _rules_modified=0
    for _iptables in $for_iptables; do
        case "$1" in
            "add")
                if ! $_iptables -nL "$CHAIN" > /dev/null 2>&1; then
                    _rules_modified=1

                    $_iptables -N "$CHAIN"
                    $_iptables -I "$CHAIN" -j REJECT

                    _wan_interface="$(get_wan_interface)"
                    verify_bridge_interfaces

                    for _bridge_interface in $BRIDGE_INTERFACES; do
                        $_iptables -I FORWARD -i "$_bridge_interface" -o "$_wan_interface" -j "$CHAIN"

                        logger -st "$script_name" "Enabled VPN Kill-switch on bridge interface: $_bridge_interface"
                    done
                fi
            ;;
            "remove")
                if $_iptables -nL "$CHAIN" > /dev/null 2>&1; then
                    _rules_modified=-1

                    _wan_interface="$(get_wan_interface)"
                    verify_bridge_interfaces

                    for _bridge_interface in $BRIDGE_INTERFACES; do
                        $_iptables -D FORWARD -i "$_bridge_interface" -o "$_wan_interface" -j "$CHAIN"

                        logger -st "$script_name" "Disabled VPN Kill-switch on bridge interface: $_bridge_interface"
                    done

                    $_iptables -F "$CHAIN"
                    $_iptables -X "$CHAIN"
                fi
            ;;
        esac
    done

    [ -n "$EXECUTE_COMMAND" ] && [ "$_rules_modified" -ne 0 ] && $EXECUTE_COMMAND "$1"

    lockfile unlock
}

case "$1" in
    "run")
        firewall_rules add
    ;;
    "start")
        firewall_rules add

        if [ "$RUN_EVERY_MINUTE" = true ]; then
            if [ -x "$script_dir/cron-queue.sh" ]; then
                sh "$script_dir/cron-queue.sh" add "$script_name" "$script_path run"
            else
                cru a "$script_name" "*/1 * * * * $script_path run"
            fi
        fi
    ;;
    "stop")
        [ -x "$script_dir/cron-queue.sh" ] && sh "$script_dir/cron-queue.sh" remove "$script_name"
        cru d "$script_name"

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
