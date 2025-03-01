#!/bin/sh
# Made by Jack'lul <jacklul.github.io>
#
# Modifies CPU affinity mask of defined processes
#

#jacklul-asuswrt-scripts-update=process-affinity.sh
#shellcheck disable=SC2155,SC2009

readonly script_path="$(readlink -f "$0")"
readonly script_name="$(basename "$script_path" .sh)"
readonly script_dir="$(dirname "$script_path")"
readonly script_config="$script_dir/$script_name.conf"

PROCESS_AFFINITIES="crond" # List of processes and affinity masks in format "process1:6 process2:4", specify only the process name to set it to /sbin/init affinity minus one

if [ -f "$script_config" ]; then
    #shellcheck disable=SC1090
    . "$script_config"
fi

# PROCESS_AFFINITY was renamed, do not break people's configuration @TODO Remove it someday...
[ -n "$PROCESS_AFFINITY" ] && PROCESS_AFFINITIES="$PROCESS_AFFINITY"

init_affinity="$(taskset -p 1 | sed 's/.*: //')"
init_affinity=$((0x$init_affinity))
if ! echo "$init_affinity" | grep -q '^[0-9]\+$'; then
    unset init_affinity
fi

set_affinity() {
    [ -z "$1" ] && { echo "You must specify a process name"; exit 1; }
    [ -z "$2" ] && { echo "You must specify an affinity mask"; exit 1; }

    _process_basename="$(basename "$1")"

    if echo "$1" | grep -q "/"; then
        _process_path="$(readlink -f "$1")"
    else
        _process_path="$(readlink -f "$(which "$1")")"
    fi

    [ -z "$_process_path" ] && { echo "Executable '$_process_path' not found"; return; }

    for _pid in $(pidof "$_process_basename"); do
        _actual_process_path="$(readlink -f "/proc/$_pid/exe")"

        if [ "$_process_path" != "$_actual_process_path" ]; then
            echo "Executable path mismatch for '$_process_basename' (PID $_pid) ('$_process_path' != '$_actual_process_path')"
            continue
        fi

        _pid_affinity="$(taskset -p "$_pid" | sed 's/.*: //')"

        if ! echo "$_pid_affinity" | grep -Eq '^[0-9]+$'; then
            echo "Failed to get CPU affinity mask of '$_process_basename' (PID $_pid)"
            continue
        fi

        if [ "$_pid_affinity" -ne "$2" ]; then
            if taskset -p "$2" "$_pid" >/dev/null; then
                logger -st "$script_name" "Changed CPU affinity mask of '$_process_basename' (PID $_pid) from $_pid_affinity to $2"
            else
                logger -st "$script_name" "Failed to change CPU affinity mask of '$_process_basename' (PID $_pid) from $_pid_affinity to $2"
            fi
        fi
    done
}

process_affinity() {
    if [ -n "$init_affinity" ]; then
        init_affinity_minus_one=$((init_affinity - 1))

        if [ "$init_affinity_minus_one" -le 0 ]; then
            unset init_affinity_minus_one
        else
            init_affinity_minus_one=$(printf '%x\n' "$init_affinity_minus_one")
        fi
    fi

    for _process in $PROCESS_AFFINITIES; do
        _affinity=$init_affinity_minus_one

        case $1 in
            "set")
                if echo "$_process" | grep -q ":"; then
                    _affinity="$(echo "$_process" | cut -d ':' -f 2 2> /dev/null)"
                    _process="$(echo "$_process" | cut -d ':' -f 1 2> /dev/null)"

                    echo "$_process" | grep -q ":" && { echo "Failed to parse list element: $_process"; exit 1; } # no 'cut' command?
                fi
            ;;
            "unset")
                _affinity=$init_affinity
            ;;
        esac

        if [ -n "$_affinity" ]; then
            set_affinity "$_process" "$_affinity"
        else
            echo "Failed to change CPU affinity mask of '$_process' - no mask specified"
        fi
    done
}

case $1 in
    "run")
        process_affinity set
    ;;
    "start")
        { [ ! -f /usr/bin/taskset ] && [ ! -f /opt/bin/taskset ] ; } && { logger -st "$script_name" "Command 'taskset' not found"; exit 1; }

        if [ -x "$script_dir/cron-queue.sh" ]; then
            sh "$script_dir/cron-queue.sh" add "$script_name" "$script_path run"
        else
            cru a "$script_name" "*/1 * * * * $script_path run"
        fi

        process_affinity set
    ;;
    "stop")
        cru d "$script_name"

        if [ -n "$init_affinity" ]; then
            process_affinity unset
        else
            echo "Changes made by this script cannot be reverted because the initial affinity mask is unknown - restart the process(es) to restore the original affinity mask(s)"
        fi
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
