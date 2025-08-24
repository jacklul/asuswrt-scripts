#!/bin/sh
# Made by Jack'lul <jacklul.github.io>
#
# Runs "every minute" jobs one after another to decrease performance impact
# This only applies to scripts from jacklul/asuswrt-script repository
#

#jacklul-asuswrt-scripts-update=cron-queue.sh
#shellcheck disable=SC2155

readonly script_path="$(readlink -f "$0")"
readonly script_name="$(basename "$script_path" .sh)"
readonly script_dir="$(dirname "$script_path")"
readonly script_config="$script_dir/$script_name.conf"

QUEUE_FILE="/tmp/cron_queue" # where to store the queue

umask 022 # set default umask

if [ -f "$script_config" ]; then
    #shellcheck disable=SC1090
    . "$script_config"
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
        [ "$_lfd_min" -gt "$_lfd_max" ] && { logger -st "$script_name" "Error: No free file descriptors available"; exit 1; }
    done

    echo "$_lfd_min"
} #LOCKFILE_END#

case "$1" in
    "run")
        lockfile lockwait run # make sure queue list does not get written to while running

        #shellcheck disable=SC1090
        #( sh "$QUEUE_FILE" < /dev/null )

        while IFS= read -r line; do
            line=$(echo "$line" | sed 's/[[:space:]]*#.*$//; s/^[[:space:]]*//; s/[[:space:]]*$//')
            [ -z "$line" ] && continue
            echo "Running: $line"
            #shellcheck disable=SC2086
            ( $line < /dev/null )
        done < "$QUEUE_FILE"

        lockfile unlock run
    ;;
    "add"|"remove"|"delete"|"a"|"r"|"d")
        add="$1"
        [ "$1" = "a" ] && add=add

        [ -z "$2" ] && { echo "Entry ID not set"; exit 1; }
        { [ -z "$3" ] && [ "$add" = "add" ] ; } && { echo "Entry command not set"; exit 1; }

        lockfile lockwait

        [ -f "$QUEUE_FILE" ] && sed "/#$(echo "$2" | sed 's/[]\/$*.^&[]/\\&/g')#$/d" -i "$QUEUE_FILE"
        [ "$add" = "add" ] && echo "$3 #$2#" >> "$QUEUE_FILE"

        lockfile unlock
    ;;
    "list"|"l")
        if [ -f "$QUEUE_FILE" ]; then
            cat "$QUEUE_FILE"
        else
            echo "Queue file does not exist"
        fi
    ;;
    "check"|"c")
        [ -z "$2" ] && { echo "Entry ID not provided"; exit 1; }

        if [ -f "$QUEUE_FILE" ]; then
            grep -Fq "#$2#" "$QUEUE_FILE" && exit 0
        fi

        exit 1
    ;;
    "start")
        cru a "$script_name" "*/1 * * * * $script_path run"
    ;;
    "stop")
        cru d "$script_name"
    ;;
    "restart")
        sh "$script_path" stop
        sh "$script_path" start
    ;;
    *)
        echo "Usage: $0 run|start|stop|restart|add|remove|list|check"
        exit 1
    ;;
esac
