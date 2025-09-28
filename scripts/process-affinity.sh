#!/bin/sh
# Made by Jack'lul <jacklul.github.io>
#
# Modify CPU affinity mask of defined processes
#

#jas-update=process-affinity.sh
#shellcheck disable=SC2155
#shellcheck source=./common.sh
readonly common_script="$(dirname "$0")/common.sh"
if [ -f "$common_script" ]; then . "$common_script"; else { echo "$common_script not found" >&2; exit 1; } fi

PROCESS_AFFINITIES="" # List of processes and affinity masks, in format 'process1=6 process2=4', specify only the process name to set it to /sbin/init affinity minus one

load_script_config

init_affinity="$(taskset -p 1 2> /dev/null | sed 's/.*: //')"
[ -n "$init_affinity" ] && init_affinity=$((0x$init_affinity))
if ! echo "$init_affinity" | grep -q '^[0-9]\+$'; then
    unset init_affinity
fi

set_affinity() {
    [ -z "$1" ] && { echo "You must specify a process name" >&2; exit 1; }
    [ -z "$2" ] && { echo "You must specify an affinity mask" >&2; exit 1; }

    _process_basename="$(basename "$1")"

    if echo "$1" | grep -Fq "/"; then
        _process_path="$(readlink -f "$1")"
    else
        _process_path="$(readlink -f "$(PATH=/bin:/usr/bin:/sbin:/usr/sbin:/opt/sbin:/opt/bin which "$1")")"
    fi

    [ -z "$_process_path" ] && { echo "Executable '$_process_path' not found" >&2; return; }

    for _pid in $(pidof "$_process_basename"); do
        _actual_process_path="$(readlink -f "/proc/$_pid/exe")"

        if [ "$_process_path" != "$_actual_process_path" ]; then
            echo "Executable path mismatch for '$_process_basename' (PID $_pid) ('$_process_path' != '$_actual_process_path')" >&2
            continue
        fi

        _pid_affinity="$(taskset -p "$_pid" | sed 's/.*: //')"

        if ! echo "$_pid_affinity" | grep -Eq '^[0-9]+$'; then
            echo "Failed to get CPU affinity mask of '$_process_basename' (PID $_pid)" >&2
            continue
        fi

        if [ "$_pid_affinity" -ne "$2" ]; then
            if taskset -p "$2" "$_pid" > /dev/null; then
                logecho "Changed CPU affinity mask of '$_process_basename' (PID $_pid) from $_pid_affinity to $2" logger
            else
                logecho "Failed to change CPU affinity mask of '$_process_basename' (PID $_pid) from $_pid_affinity to $2" error
            fi
        fi
    done
}

process_affinity() {
    type taskset > /dev/null 2>&1 || { logecho "Error: Command 'taskset' not found" error; exit 1; }
    [ -z "$PROCESS_AFFINITIES" ] && { logecho "Error: PROCESS_AFFINITIES is not set" error; exit 1; }

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
                if echo "$_process" | grep -Fq "="; then
                    _affinity="$(echo "$_process" | cut -d '=' -f 2 2> /dev/null)"
                    _process="$(echo "$_process" | cut -d '=' -f 1 2> /dev/null)"

                    echo "$_process" | grep -Fq "=" && { echo "Failed to parse list element: $_process" >&2; exit 1; } # no 'cut' command?
                fi
            ;;
            "unset")
                _affinity=$init_affinity
            ;;
        esac

        if [ -n "$_affinity" ]; then
            set_affinity "$_process" "$_affinity"
        else
            echo "Failed to change CPU affinity mask of '$_process' - no mask specified" >&2
        fi
    done
}

case $1 in
    "run")
        process_affinity set
    ;;
    "start")
        process_affinity set
        crontab_entry add "*/1 * * * * $script_path run"
    ;;
    "stop")
        crontab_entry delete

        if [ -n "$init_affinity" ]; then
            process_affinity unset
        else
            echo "Changes made by this script cannot be reverted because the initial affinity mask is unknown - restart the process(es) to restore the original affinity masks"
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
