#!/bin/sh
# Made by Jack'lul <jacklul.github.io>
#
# Download files from netboot.xyz to specified directory
#
# Based on:
#  https://github.com/RMerl/asuswrt-merlin.ng/wiki/Enable-PXE-booting-into-netboot.xyz
#

#jacklul-asuswrt-scripts-update=netboot-download.sh
#shellcheck disable=SC2155

readonly script_path="$(readlink -f "$0")"
readonly script_name="$(basename "$script_path" .sh)"
readonly script_dir="$(dirname "$script_path")"
readonly script_config="$script_dir/$script_name.conf"

FILES="netboot.xyz.efi netboot.xyz.kpxe" # what files to download, space separated
DIRECTORY="/tmp/netboot.xyz" # where to save the files
BASE_URL="https://boot.netboot.xyz/ipxe" # base download URL, without ending slash

umask 022 # set default umask

if [ -f "$script_config" ]; then
    #shellcheck disable=SC1090
    . "$script_config"
fi

curl_binary="curl"
[ -f /opt/bin/curl ] && curl_binary="/opt/bin/curl" # prefer Entware's curl as it is not modified by Asus

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

case "$1" in
    "run")
        lockfile lockfail || { echo "Already running! ($_lockpid)"; exit 1; }

        { [ "$(nvram get wan0_state_t)" != "2" ] && [ "$(nvram get wan1_state_t)" != "2" ] ; } && { echo "WAN network is not connected"; exit 1; }
        [ -z "$($curl_binary -fs "https://boot.netboot.xyz")" ] && { echo "Cannot reach boot.netboot.xyz"; exit 1; }

        #logger -st "$script_name" "Downloading files from netboot.xyz..."

        #shellcheck disable=SC2174
        [ ! -d "$DIRECTORY" ] && mkdir -p "$DIRECTORY"

        downloaded=""
        failed=""
        for file in $FILES; do
            [ -f "$DIRECTORY/$file" ] && continue

            if $curl_binary -fsSL "$BASE_URL/$file" -o "$DIRECTORY/$file" && [ -f "$DIRECTORY/$file" ]; then
                downloaded="$downloaded $file"
            else
                failed="$failed $file"
            fi
        done

        [ -n "$downloaded" ] && logger -st "$script_name" "Downloaded files from netboot.xyz:$downloaded"
        #[ -n "$failed" ] && logger -st "$script_name" "Failed to downloaded files from netboot.xyz:$failed"

        if [ -z "$failed" ]; then
            [ -x "$script_dir/cron-queue.sh" ] && sh "$script_dir/cron-queue.sh" remove "$script_name"
            cru d "$script_name"
        fi

        lockfile unlock
    ;;
    "start")
        if [ -x "$script_dir/cron-queue.sh" ]; then
            sh "$script_dir/cron-queue.sh" add "$script_name" "$script_path run"
        else
            cru a "$script_name" "*/1 * * * * $script_path run"
        fi

        if is_started_by_system; then
            {
                sh "$script_path" run
            } &
        else
            sh "$script_path" run
        fi
    ;;
    "stop")
        [ -x "$script_dir/cron-queue.sh" ] && sh "$script_dir/cron-queue.sh" remove "$script_name"
        cru d "$script_name"

        lockfile kill
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
