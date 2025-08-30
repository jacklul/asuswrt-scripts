#!/bin/sh
# Made by Jack'lul <jacklul.github.io>
#
# Kills specified processes/modules and prevents them from starting
#
# Based on:
#  https://www.snbforums.com/threads/i-would-like-to-kill-some-of-the-processes-permanently.47616/#post-416517
#
# Known limitations:
#  Cannot block files that are symlinked
#

#jacklul-asuswrt-scripts-update=process-killer.sh
#shellcheck disable=SC2155

readonly script_path="$(readlink -f "$0")"
readonly script_name="$(basename "$script_path" .sh)"
readonly script_dir="$(dirname "$script_path")"
readonly script_config="$script_dir/$script_name.conf"

PROCESSES_TO_KILL="" # processes/kernel modules to kill and block

if [ -f "$script_config" ]; then
    #shellcheck disable=SC1090
    . "$script_config"
fi

case "$1" in
    "run")
        if [ -n "$PROCESSES_TO_KILL" ]; then
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
                        lsmod | grep -Fq "$modulename" && modprobe -r "$modulename" && logger -st "$script_name" "Blocked kernel module: $process" && usleep 250000
                        mount -o bind /dev/null "$filepath"
                    fi
                else
                    [ -n "$(pidof "$filename")" ] && killall "$filename" && logger -st "$script_name" "Killed process: $process"

                    if [ -f "$filepath" ] && [ ! -h "$filepath" ]; then
                        usleep 250000
                        mount -o bind /dev/null "$filepath"
                    fi
                fi
            done
        fi
    ;;
    "start")
        if [ "$(awk -F '.' '{print $1}' /proc/uptime)" -lt 300 ]; then
            { sleep 60 && sh "$script_path" run; } & # delay when freshly booted
        else
            sh "$script_path" run
        fi
    ;;
    "stop")
        logger -st "$script_name" "Operations made by this script cannot be reverted - disable it then reboot the router!"
    ;;
    "restart")
        sh "$script_path" start
    ;;
    *)
        echo "Usage: $0 run|start|stop|restart"
        exit 1
    ;;
esac
