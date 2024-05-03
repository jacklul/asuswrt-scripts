#!/bin/sh
# Made by Jack'lul <jacklul.github.io>
#
# Enables VPN clients to access Samba shares in LAN
#

#jacklul-asuswrt-scripts-update
#shellcheck disable=SC2155

readonly SCRIPT_PATH="$(readlink -f "$0")"
readonly SCRIPT_NAME="$(basename "$SCRIPT_PATH" .sh)"
readonly SCRIPT_DIR="$(dirname "$SCRIPT_PATH")"
readonly SCRIPT_CONFIG="$SCRIPT_DIR/$SCRIPT_NAME.conf"
readonly SCRIPT_TAG="$(basename "$SCRIPT_PATH")"

VPN_NETWORKS="10.6.0.0/24 10.8.0.0/24 10.10.10.0/24" # VPN networks (IPv4) to allow access to Samba from, separated by spaces
VPN_NETWORKS6="" # VPN networks (IPv6) to allow access to Samba from, separated by spaces
BRIDGE_INTERFACE="br0" # the bridge interface to set rules for, by default only LAN bridge ("br0") interface
EXECUTE_COMMAND="" # execute a command after firewall rules are applied or removed (receives arguments: $1 = action)

if [ -f "$SCRIPT_CONFIG" ]; then
    #shellcheck disable=SC1090
    . "$SCRIPT_CONFIG"
fi

CHAIN="SAMBA_MASQUERADE"
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
                echo "File descriptor $_FD is already in use ($(readlink -f "/proc/$$/fd/$_FD"))"
                _FD=$((_FD+1))

                [ "$_FD" -gt "$_FD_MAX" ] && exit 1
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

firewall_rules() {
    [ -z "$BRIDGE_INTERFACE" ] && { logger -st "$SCRIPT_TAG" "Bridge interface is not set"; exit 1; }
    [ -z "$VPN_NETWORKS" ] && { logger -st "$SCRIPT_TAG" "Allowed VPN networks are not set"; exit 1; }

    lockfile lockwait

    _RULES_ADDED=0
    for _IPTABLES in $FOR_IPTABLES; do
        if [ "$_IPTABLES" = "ip6tables" ]; then
            _VPN_NETWORKS="$VPN_NETWORKS6"
        else
            _VPN_NETWORKS="$VPN_NETWORKS"
        fi

        [ -z "$_VPN_NETWORKS" ] && continue

        _DESTINATION_NETWORK="$($_IPTABLES -t nat -nvL POSTROUTING --line-numbers | grep -E " MASQUERADE .*$BRIDGE_INTERFACE" | head -1 | awk '{print $9}')"

        case "$1" in
            "add")
                if ! $_IPTABLES -t nat -nL "$CHAIN" > /dev/null 2>&1; then
                    _RULES_ADDED=1

                    $_IPTABLES -t nat -N "$CHAIN"
                    $_IPTABLES -t nat -A "$CHAIN" -p tcp --dport 445 -j MASQUERADE
                    $_IPTABLES -t nat -A "$CHAIN" -p tcp --dport 139 -j MASQUERADE
                    $_IPTABLES -t nat -A "$CHAIN" -p udp --dport 138 -j MASQUERADE
                    $_IPTABLES -t nat -A "$CHAIN" -p udp --dport 137 -j MASQUERADE
                    $_IPTABLES -t nat -A "$CHAIN" -p icmp --icmp-type 1 -j MASQUERADE
                    $_IPTABLES -t nat -A "$CHAIN" -j RETURN

                    for _VPN_NETWORK in $_VPN_NETWORKS; do
                        if [ -n "$_DESTINATION_NETWORK" ]; then
                            $_IPTABLES -t nat -A POSTROUTING -s "$_VPN_NETWORK" -d "$_DESTINATION_NETWORK" -o "$BRIDGE_INTERFACE" -j "$CHAIN"
                        else
                            $_IPTABLES -t nat -A POSTROUTING -s "$_VPN_NETWORK" -o "$BRIDGE_INTERFACE" -j "$CHAIN"
                        fi
                    done
                fi
            ;;
            "remove")
                if $_IPTABLES -t nat -nL "$CHAIN" > /dev/null 2>&1; then
                    for _VPN_NETWORK in $_VPN_NETWORKS; do
                        if [ -n "$_DESTINATION_NETWORK" ] && $_IPTABLES -t nat -C POSTROUTING -s "$_VPN_NETWORK" -d "$_DESTINATION_NETWORK" -o "$BRIDGE_INTERFACE" -j "$CHAIN" > /dev/null 2>&1; then
                            $_IPTABLES -t nat -D POSTROUTING -s "$_VPN_NETWORK" -d "$_DESTINATION_NETWORK" -o "$BRIDGE_INTERFACE" -j "$CHAIN"
                        fi

                        if $_IPTABLES -t nat -C POSTROUTING -s "$_VPN_NETWORK" -o "$BRIDGE_INTERFACE" -j "$CHAIN" > /dev/null 2>&1; then
                            $_IPTABLES -t nat -D POSTROUTING -s "$_VPN_NETWORK" -o "$BRIDGE_INTERFACE" -j "$CHAIN"
                        fi
                    done

                    $_IPTABLES -t nat -F "$CHAIN"
                    $_IPTABLES -t nat -X "$CHAIN"
                fi
            ;;
        esac
    done

    [ "$_RULES_ADDED" = 1 ] && logger -st "$SCRIPT_TAG" "Masquerading Samba connections from networks: $(echo "$VPN_NETWORKS $VPN_NETWORKS6" | awk '{$1=$1};1')"

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
