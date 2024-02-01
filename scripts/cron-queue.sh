#!/bin/sh
# Made by Jack'lul <jacklul.github.io>
#
# Runs "every minute" jobs one after another
#

# jacklul-asuswrt-scripts-update
#shellcheck disable=SC2155,SC2009

readonly SCRIPT_PATH="$(readlink -f "$0")"
readonly SCRIPT_NAME="$(basename "$SCRIPT_PATH" .sh)"
readonly SCRIPT_DIR="$(dirname "$SCRIPT_PATH")"
readonly SCRIPT_CONFIG="$SCRIPT_DIR/$SCRIPT_NAME.conf"

QUEUE_FILE="/tmp/cron_queue"

if [ -f "$SCRIPT_CONFIG" ]; then
    #shellcheck disable=SC1090
    . "$SCRIPT_CONFIG"
fi

lockfile() { #LOCKFILE_START#
    _LOCKFILE="/var/lock/script-$SCRIPT_NAME.lock"
    _PIDFILE="/var/run/script-$SCRIPT_NAME.pid"
    _FD=9

    if [ -n "$2" ]; then
        _LOCKFILE="/var/lock/script-$SCRIPT_NAME-$2.lock"
        _PIDFILE="/var/run/script-$SCRIPT_NAME-$2.lock"
    fi

    [ -n "$3" ] && [ "$3" -eq "$3" ] && _FD="$3"

    _LOCKPID=
    [ -f "$_PIDFILE" ] && _LOCKPID="$(cat "$_PIDFILE")"

    case "$1" in
        "lockwait"|"lockfail"|"lockexit")
            eval exec "$_FD>$_LOCKFILE"

            case "$1" in
                "lockwait"|"lock")
                    flock -x "$_FD"
                ;;
                "lockfail")
                    [ -n "$_LOCKPID" ] && [ -f "/proc/$_LOCKPID/stat" ] && return 1
                    flock -x "$_FD"
                ;;
                "lockexit")
                    [ -n "$_LOCKPID" ] && [ -f "/proc/$_LOCKPID/stat" ] && exit 1
                    flock -x "$_FD"
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

case "$1" in
    "run")
        lockfile lockwait run 8

        #shellcheck disable=SC1090
        . "$QUEUE_FILE"

        lockfile unlock run 8
    ;;
    "add"|"remove"|"delete")
        [ -z "$2" ] && { echo "Entry ID not set"; exit 1; }
        { [ -z "$3" ] && [ "$1" = "add" ] ; } && { echo "Entry command not set"; exit 1; }

        lockfile lockwait

        [ -f "$QUEUE_FILE" ] && sed "/#$(echo "$2" | sed 's/[]\/$*.^&[]/\\&/g')#$/d" -i "$QUEUE_FILE"
        [ "$1" = "add" ] && echo "$3 #$2#" >> "$QUEUE_FILE"

        lockfile unlock
    ;;
    "list")
        if [ -f "$QUEUE_FILE" ]; then
            cat "$QUEUE_FILE"
        else
            echo "Queue file does not exist"
        fi
    ;;
    "check")
        [ -z "$2" ] && { echo "Entry ID not provided"; exit 1; }

        if [ -f "$QUEUE_FILE" ]; then
            grep -q "#$2#" "$QUEUE_FILE" && exit 0
        fi

        exit 1
    ;;
    "start")
        cru a "$SCRIPT_NAME" "*/1 * * * * $SCRIPT_PATH run"
    ;;
    "stop")
        cru d "$SCRIPT_NAME"
    ;;
    "restart")
        sh "$SCRIPT_PATH" stop
        sh "$SCRIPT_PATH" start
    ;;
    *)
        echo "Usage: $0 run|start|stop|restart|add|remove|list|check"
        exit 1
    ;;
esac
