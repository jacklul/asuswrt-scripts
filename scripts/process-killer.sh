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

#shellcheck disable=SC2155

readonly SCRIPT_PATH="$(readlink -f "$0")"
readonly SCRIPT_NAME="$(basename "$SCRIPT_PATH" .sh)"
readonly SCRIPT_DIR="$(dirname "$SCRIPT_PATH")"
readonly SCRIPT_CONFIG="$SCRIPT_DIR/$SCRIPT_NAME.conf"

PROCESSES_TO_KILL="" # processes/kernel modules to kill and block

# This means that this is a Merlin firmware
if [ -f "/usr/sbin/helper.sh" ]; then
    #shellcheck disable=SC1091
    . /usr/sbin/helper.sh

    PROCESSES_TO_KILL_=$(am_settings_get jl_pkiller_processes)

    [ -n "$PROCESSES_TO_KILL_" ] && PROCESSES_TO_KILL=$PROCESSES_TO_KILL_
fi

if [ -f "$SCRIPT_CONFIG" ]; then
    #shellcheck disable=SC1090
    . "$SCRIPT_CONFIG"
fi

case "$1" in
    "run")
        if [ -n "$PROCESSES_TO_KILL" ]; then
            for PROCESS in $(echo "$PROCESSES_TO_KILL" | grep -o -e "[^ ]*"); do
                FILEPATH="$PROCESS"

                if [ ! -f "$FILEPATH" ]; then
                    TMP=$(which "$PROCESS")

                    [ -n "$TMP" ] && FILEPATH=$TMP
                fi

                [ -f "$FILEPATH" ] && mount | grep "$FILEPATH" > /dev/null && continue

                FILENAME="$(basename "$FILEPATH")"
                FILEEXT="${FILENAME##*.}"

                if [ "$FILEEXT" = "ko" ]; then
                    MODULENAME="${FILENAME%.*}"
                    FILEPATH="/lib/modules/$(uname -r)/$(modprobe -l "$MODULENAME")"

                    if [ -f "$FILEPATH" ] && [ ! -h "$FILEPATH" ]; then
                        lsmod | grep -qF "$MODULENAME" && modprobe -r "$MODULENAME" && logger -s -t "$SCRIPT_NAME" "Blocked kernel module: $PROCESS" && usleep 250000
                        mount -o bind /dev/null "$FILEPATH"
                    fi
                else
                    [ -n "$(pidof "$FILENAME")" ] && killall "$FILENAME" && logger -s -t "$SCRIPT_NAME" "Killed process: $PROCESS"

                    if [ -f "$FILEPATH" ] && [ ! -h "$FILEPATH" ]; then
                        usleep 250000
                        mount -o bind /dev/null "$FILEPATH"
                    fi
                fi
            done
        fi
    ;;
    "start")
        if [ "$(awk -F '.' '{print $1}' /proc/uptime)" -lt "300" ]; then
            { sleep 60 && sh "$SCRIPT_PATH" run; } & # delay when freshly booted
        else
            sh "$SCRIPT_PATH" run
        fi
    ;;
    "stop")
        logger -s -t "$SCRIPT_NAME" "Operations made by this script cannot be reverted - disable it then reboot the router!"
    ;;
    "restart")
        sh "$SCRIPT_PATH" start
    ;;
    *)
        echo "Usage: $0 run|start|stop|restart"
        exit 1
    ;;
esac
