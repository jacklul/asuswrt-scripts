#!/bin/sh
# Made by Jack'lul <jacklul.github.io>
#
# Modifies CPU affinity mask of defined processes
#

#jacklul-asuswrt-scripts-update=process-affinity.sh
#shellcheck disable=SC2155,SC2009

readonly SCRIPT_PATH="$(readlink -f "$0")"
readonly SCRIPT_NAME="$(basename "$SCRIPT_PATH" .sh)"
readonly SCRIPT_DIR="$(dirname "$SCRIPT_PATH")"
readonly SCRIPT_CONFIG="$SCRIPT_DIR/$SCRIPT_NAME.conf"
readonly SCRIPT_TAG="$(basename "$SCRIPT_PATH")"

PROCESS_AFFINITIES="crond" # List of processes and affinity masks in format "process1:6 process2:4", specify only the process name to set it to /sbin/init affinity minus one

if [ -f "$SCRIPT_CONFIG" ]; then
    #shellcheck disable=SC1090
    . "$SCRIPT_CONFIG"
fi

# PROCESS_AFFINITY was renamed, do not break people's configuration @TODO Remove it someday...
[ -n "$PROCESS_AFFINITY" ] && PROCESS_AFFINITIES="$PROCESS_AFFINITY"

INIT_AFFINITY="$(taskset -p 1 | sed 's/.*: //')"
if ! echo "$INIT_AFFINITY" | grep -Eq '^[0-9]+$'; then
    unset INIT_AFFINITY
fi

set_affinity() {
    [ -z "$1" ] && { echo "You must specify a process name"; exit 1; }
    [ -z "$2" ] && { echo "You must specify an affinity mask"; exit 1; }

    _PROCESS_BASENAME="$(basename "$1")"

    if echo "$1" | grep -q "/"; then
        _PROCESS_PATH="$(readlink -f "$1")"
    else
        _PROCESS_PATH="$(readlink -f "$(which "$1")")"
    fi

    [ -z "$_PROCESS_PATH" ] && { echo "Executable '$_PROCESS_PATH' not found"; return; }

    for PID in $(pidof "$_PROCESS_BASENAME"); do
        PROCESS_PATH="$(readlink -f "/proc/$PID/exe")"

        if [ "$_PROCESS_PATH" != "$PROCESS_PATH" ]; then
            echo "Executable path mismatch for '$_PROCESS_BASENAME' (PID $PID) ('$_PROCESS_PATH' != '$PROCESS_PATH')"
            continue
        fi

        PID_AFFINITY="$(taskset -p "$PID" | sed 's/.*: //')"

        if ! echo "$PID_AFFINITY" | grep -Eq '^[0-9]+$'; then
            echo "Failed to get CPU affinity mask of '$_PROCESS_BASENAME' (PID $PID)"
            continue
        fi

        if [ "$PID_AFFINITY" -ne "$2" ]; then
            if taskset -p "$2" "$PID" >/dev/null; then
                logger -st "$SCRIPT_TAG" "Changed CPU affinity mask of '$_PROCESS_BASENAME' (PID $PID) from $PID_AFFINITY to $2"
            else
                logger -st "$SCRIPT_TAG" "Failed to change CPU affinity mask of '$_PROCESS_BASENAME' (PID $PID) from $PID_AFFINITY to $2"
            fi
        fi
    done
}

process_affinity() {
    if [ -n "$INIT_AFFINITY" ]; then
        INIT_AFFINITY_MINUS_ONE=$((INIT_AFFINITY - 1))

        if [ "$INIT_AFFINITY_MINUS_ONE" -le 0 ]; then
            unset INIT_AFFINITY_MINUS_ONE
        fi
    fi

    for _PROCESS in $PROCESS_AFFINITIES; do
        _AFFINITY=$INIT_AFFINITY_MINUS_ONE

        case $1 in
            "set")
                if echo "$_PROCESS" | grep -q ":"; then
                    _AFFINITY="$(echo "$_PROCESS" | cut -d ':' -f 2 2> /dev/null)"
                    _PROCESS="$(echo "$_PROCESS" | cut -d ':' -f 1 2> /dev/null)"

                    echo "$_PROCESS" | grep -q ":" && { echo "Failed to parse list element: $_PROCESS"; exit 1; } # no 'cut' command?
                fi
            ;;
            "unset")
                _AFFINITY=$INIT_AFFINITY
            ;;
        esac

        if [ -n "$_AFFINITY" ]; then
            set_affinity "$_PROCESS" "$_AFFINITY"
        else
            echo "Failed to change CPU affinity mask of '$_PROCESS' - no mask specified"
        fi
    done
}

case $1 in
    "run")
        process_affinity set
    ;;
    "start")
        { [ ! -f /usr/bin/taskset ] && [ ! -f /opt/bin/taskset ] ; } && { logger -st "$SCRIPT_TAG" "Command 'taskset' not found"; exit 1; }

        if [ -x "$SCRIPT_DIR/cron-queue.sh" ]; then
            sh "$SCRIPT_DIR/cron-queue.sh" add "$SCRIPT_NAME" "$SCRIPT_PATH run"
        else
            cru a "$SCRIPT_NAME" "*/1 * * * * $SCRIPT_PATH run"
        fi

        process_affinity set
    ;;
    "stop")
        cru d "$SCRIPT_NAME"

        if [ -n "$INIT_AFFINITY" ]; then
            process_affinity unset
        else
            echo "Changes made by this script cannot be reverted because the initial affinity mask is unknown - restart the process(es) to restore the original affinity mask(s)"
        fi
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
