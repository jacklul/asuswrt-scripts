#!/bin/sh
# Made by Jack'lul <jacklul.github.io>
#
# Connects any USB networking device to your LAN
#
# To be used with devices that can use USB Gadget mode.
# Raspberry Pi Zero will probably be the best for this.
# See https://github.com/jacklul/asuswrt-usb-raspberry-pi
#

#jacklul-asuswrt-scripts-update=usb-network.sh
#shellcheck disable=SC2155

readonly script_path="$(readlink -f "$0")"
readonly script_name="$(basename "$script_path" .sh)"
readonly script_dir="$(dirname "$script_path")"
readonly script_config="$script_dir/$script_name.conf"

BRIDGE_INTERFACE="br0" # bridge interface to add into, by default LAN bridge ("br0") interface
EXECUTE_COMMAND="" # execute a command each time status changes (receives arguments: $1 = action, $2 = interface)
RUN_EVERY_MINUTE= # scan for new interfaces to add to bridge periodically (true/false), empty means false when hotplug-event.sh is available but otherwise true

if [ -f "$script_config" ]; then
    #shellcheck disable=SC1090
    . "$script_config"
fi

if [ -z "$RUN_EVERY_MINUTE" ]; then
    [ ! -x "$script_dir/service-event.sh" ] && RUN_EVERY_MINUTE=true
fi

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
        [ "$_lfd_min" -gt "$_lfd_max" ] && { logger -st "$script_name" "No free file descriptors available"; exit 1; }
    done

    echo "$_lfd_min"
} #LOCKFILE_END#

is_interface_up() {
    [ ! -d "/sys/class/net/$1" ] && return 1

    _operstate="$(cat "/sys/class/net/$1/operstate")"

    case "$_operstate" in
        "up")
            return 0
        ;;
        "unknown")
            [ "$(cat "/sys/class/net/$1/carrier")" = "1" ] && return 0
        ;;
    esac

    # All other states: down, notpresent, lowerlayerdown, testing, dormant
    return 1
}

setup_inteface() {
    [ -z "$BRIDGE_INTERFACE" ] && { logger -st "$script_name" "Bridge interface is not set"; exit 1; }
    [ -z "$2" ] && { echo "You must specify a network interface"; exit 1; }

    lockfile lockwait

    case "$1" in
        "add")
            [ ! -d "/sys/class/net/$2" ] && return

            if ! is_interface_up "$2"; then
                logger -st "$script_name" "Bringing interface $2 up..."
                ifconfig "$2" up
            fi

            if ! brctl show "$BRIDGE_INTERFACE" | grep -Fq "$2" && brctl addif "$BRIDGE_INTERFACE" "$2"; then
                logger -st "$script_name" "Added interface $2 to bridge $BRIDGE_INTERFACE"
            fi
        ;;
        "remove")
            if brctl show "$BRIDGE_INTERFACE" | grep -Fq "$2" && brctl delif "$BRIDGE_INTERFACE" "$2"; then
                logger -st "$script_name" "Removed interface $2 from bridge $BRIDGE_INTERFACE"
            fi

            if [ -d "/sys/class/net/$2" ] && is_interface_up "$2"; then
                logger -st "$script_name" "Taking interface $2 down..."
                ifconfig "$2" down
            fi
        ;;
    esac

    # no extra condition needed, already handled outside this function
    [ -n "$EXECUTE_COMMAND" ] && $EXECUTE_COMMAND "$1" "$2"

    lockfile unlock
}

case "$1" in
    "run")
        bridge_members="$(brctl show "$BRIDGE_INTERFACE")"

        for interface in /sys/class/net/usb*; do
            [ ! -d "$interface" ] && continue

            interface="$(basename "$interface")"

            if ! echo "$bridge_members" | grep -Fq "$interface"; then
                setup_inteface add "$interface"
            fi
        done
    ;;
    "hotplug")
        if [ "$(echo "$DEVICENAME" | cut -c 1-3)" = "usb" ]; then
            case "$ACTION" in
                "add")
                    setup_inteface add "$DEVICENAME"
                ;;
                "remove")
                    setup_inteface remove "$DEVICENAME"
                ;;
            esac
        fi
    ;;
    "start")
        [ -z "$BRIDGE_INTERFACE" ] && { logger -st "$script_name" "Unable to start - bridge interface is not set"; exit 1; }

        if [ "$RUN_EVERY_MINUTE" = true ]; then
            if [ -x "$script_dir/cron-queue.sh" ]; then
                sh "$script_dir/cron-queue.sh" add "$script_name" "$script_path run"
            else
                cru a "$script_name" "*/1 * * * * $script_path run"
            fi
        fi

        for interface in /sys/class/net/usb*; do
            [ -d "$interface" ] && setup_inteface add "$(basename "$interface")"
        done
    ;;
    "stop")
        [ -x "$script_dir/cron-queue.sh" ] && sh "$script_dir/cron-queue.sh" remove "$script_name"
        cru d "$script_name"

        for interface in /sys/class/net/usb*; do
            [ -d "$interface" ] && setup_inteface remove "$(basename "$interface")"
        done
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
