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

readonly SCRIPT_PATH="$(readlink -f "$0")"
readonly SCRIPT_NAME="$(basename "$SCRIPT_PATH" .sh)"
readonly SCRIPT_DIR="$(dirname "$SCRIPT_PATH")"
readonly SCRIPT_CONFIG="$SCRIPT_DIR/$SCRIPT_NAME.conf"
readonly SCRIPT_TAG="$(basename "$SCRIPT_PATH")"

# `nvram get apg_ifnames` command will list you the current bridge interfaces excluding br0 in case you need to
# selectively pick one or more of the bridge interfaces, separated by spaces
BRIDGE_INTERFACES="br+" # the bridge interface to set rules for, by default affects all "br" interfaces (which also includes guest network bridge)
EXECUTE_COMMAND="" # execute a command after firewall rules are applied or removed (receives arguments: $1 = action)

if [ -f "$SCRIPT_CONFIG" ]; then
    #shellcheck disable=SC1090
    . "$SCRIPT_CONFIG"
fi

CHAIN="VPN_KILLSWITCH"
FOR_IPTABLES="iptables"

[ "$(nvram get ipv6_service)" != "disabled" ] && FOR_IPTABLES="$FOR_IPTABLES ip6tables"

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

get_wan_interface() {
    _INTERFACE="$(nvram get wan0_ifname)"

    if [ "$(nvram get wan0_gw_ifname)" != "$_INTERFACE" ]; then
        _INTERFACE=$(nvram get wan0_gw_ifname)
    fi

    if [ -n "$(nvram get wan0_pppoe_ifname)" ]; then
        _INTERFACE="$(nvram get wan0_pppoe_ifname)"
    fi

    echo "$_INTERFACE"
}

firewall_rules() {
    [ -z "$BRIDGE_INTERFACES" ] && { logger -st "$SCRIPT_TAG" "Bridge interfaces are not set"; exit 1; }

    if echo "$BRIDGE_INTERFACES" | grep -q "br+"; then
        logger -st "$SCRIPT_TAG" "Applying firewall rules to all bridge interfaces [br+]"
        BRIDGE_INTERFACES="br+" # sanity set, just in case one sets "br0 br+ br23"
    else
        for _BRIDGE_INTERFACE in $BRIDGE_INTERFACES; do
            if ! ip link show | grep ": $_BRIDGE_INTERFACE" | grep -q "mtu"; then
                logger -st "$SCRIPT_TAG" "Warning: Couldn't find matching bridge interface for $_BRIDGE_INTERFACE"
                exit 0
            fi
        done
    fi

    _WAN_INTERFACE="$(get_wan_interface)"
    [ -z "$_WAN_INTERFACE" ] && { logger -st "$SCRIPT_TAG" "Couldn't get WAN interface name"; exit 1; }

    lockfile lockwait

    for _IPTABLES in $FOR_IPTABLES; do
        case "$1" in
            "add")
                if ! $_IPTABLES -nL "$CHAIN" > /dev/null 2>&1; then
                    $_IPTABLES -N "$CHAIN"
                    $_IPTABLES -I "$CHAIN" -j REJECT

                    for _BRIDGE_INTERFACE in $BRIDGE_INTERFACES; do
                        $_IPTABLES -I FORWARD -i "$_BRIDGE_INTERFACE" -o "$_WAN_INTERFACE" -j "$CHAIN"

                        logger -st "$SCRIPT_TAG" "Enabled VPN Kill-switch on bridge interface: $_BRIDGE_INTERFACE"
                    done
                fi
            ;;
            "remove")
                if $_IPTABLES -nL "$CHAIN" > /dev/null 2>&1; then
                    for _BRIDGE_INTERFACE in $BRIDGE_INTERFACES; do
                        $_IPTABLES -D FORWARD -i "$_BRIDGE_INTERFACE" -o "$_WAN_INTERFACE" -j "$CHAIN"

                        logger -st "$SCRIPT_TAG" "Disabled VPN Kill-switch on bridge interface: $_BRIDGE_INTERFACE"
                    done

                    $_IPTABLES -F "$CHAIN"
                    $_IPTABLES -X "$CHAIN"
                fi
            ;;
        esac
    done

    [ -n "$EXECUTE_COMMAND" ] && $EXECUTE_COMMAND "$1"

    lockfile unlock
}

case "$1" in
    "run")
        firewall_rules add
    ;;
    "start")
        if [ -x "$SCRIPT_DIR/cron-queue.sh" ]; then
            sh "$SCRIPT_DIR/cron-queue.sh" add "$SCRIPT_NAME" "$SCRIPT_PATH run"
        else
            cru a "$SCRIPT_NAME" "*/1 * * * * $SCRIPT_PATH run"
        fi

        firewall_rules add
    ;;
    "stop")
        [ -x "$SCRIPT_DIR/cron-queue.sh" ] && sh "$SCRIPT_DIR/cron-queue.sh" remove "$SCRIPT_NAME"
        cru d "$SCRIPT_NAME"

        firewall_rules remove
    ;;
    "restart")
        sh "$SCRIPT_PATH" stop
        sh "$SCRIPT_PATH" start
    ;;
    *)
        echo "Usage: $0 run|start|stop|restart"
        exit 1
    ;;
esac
