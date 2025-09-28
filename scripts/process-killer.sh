#!/bin/sh
# Made by Jack'lul <jacklul.github.io>
#
# Kill specified processes/modules and prevent them from restarting
#
# Based on:
#  https://www.snbforums.com/threads/i-would-like-to-kill-some-of-the-processes-permanently.47616/#post-416517
#
# Known limitations:
#  Cannot block files that are symlinked
#

#jas-update=process-killer.sh
#shellcheck disable=SC2155
#shellcheck source=./common.sh
readonly common_script="$(dirname "$0")/common.sh"
if [ -f "$common_script" ]; then . "$common_script"; else { echo "$common_script not found" >&2; exit 1; } fi

PROCESSES_TO_KILL="" # processes/kernel modules to kill and block

load_script_config

process_killer() {
    [ -z "$PROCESSES_TO_KILL" ] && { logecho "Error: PROCESSES_TO_KILL is not set" error; exit 1; }

    for process in $(echo "$PROCESSES_TO_KILL" | grep -o -e "[^ ]*"); do
        filepath="$process"

        if [ ! -f "$filepath" ]; then
            tmp=$(which "$process")

            [ -n "$tmp" ] && filepath=$tmp
        fi

        [ -f "$filepath" ] && mount | grep -F "$filepath" > /dev/null && continue

        filename="$(basename "$filepath")"
        fileext="${filename##*.}"

        if [ "$fileext" = "ko" ]; then
            modulename="${filename%.*}"
            filepath="/lib/modules/$(uname -r)/$(modprobe -l "$modulename")"

            if [ -f "$filepath" ] && [ ! -h "$filepath" ]; then
                lsmod | grep -Fq "$modulename" && modprobe -r "$modulename" && logecho "Blocked kernel module: $process" logger && usleep 250000
                mount -o bind /dev/null "$filepath"
            fi
        else
            [ -n "$(pidof "$filename")" ] && killall "$filename" && logecho "Killed process: $process" logger

            if [ -f "$filepath" ] && [ ! -h "$filepath" ]; then
                usleep 250000
                mount -o bind /dev/null "$filepath"
            fi
        fi
    done
}

case "$1" in
    "run")
        process_killer
    ;;
    "start")
        if [ ! -t 0 ] && [ "$(awk -F '.' '{print $1}' /proc/uptime)" -lt 300 ]; then
            { sleep 60 && process_killer; } & # delay when freshly booted
        else
            process_killer
        fi
    ;;
    "stop")
        logecho "Operations made by this script cannot be reverted - disable it then reboot the router!"
    ;;
    "restart")
        sh "$script_path" start
    ;;
    *)
        echo "Usage: $0 run|start|stop|restart"
        exit 1
    ;;
esac
