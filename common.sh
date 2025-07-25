#!/bin/sh
#
# This file contains common functions used across multiple scripts
# Use common-update.php script to push update to scripts using them
#

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

is_started_by_system() { #ISSTARTEDBYSYSTEM_START#
    _ppid=$PPID
    while true; do
        [ -z "$_ppid" ] && break
        _ppid=$(< "/proc/$_ppid/stat" awk '{print $4}')
        grep -Fq "cron" "/proc/$_ppid/comm" && return 0
        grep -Fq "hotplug" "/proc/$_ppid/comm" && return 0
        [ "$_ppid" -gt 1 ] || break
    done
    return 1
} #ISSTARTEDBYSYSTEM_END#

# could also be [ "$(uname -o)" = "ASUSWRT-Merlin" ] or [ -f "/www/images/merlin-logo.png" ] ?
is_merlin_firmware() { #ISMERLINFIRMWARE_START#
    if [ -f "/usr/sbin/helper.sh" ]; then
        return 0
    fi
    return 1
} #ISMERLINFIRMWARE_END#
