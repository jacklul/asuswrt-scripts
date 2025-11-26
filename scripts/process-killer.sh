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
#shellcheck shell=ash
#shellcheck disable=SC2155

#shellcheck source=./common.sh
readonly common_script="$(dirname "$0")/common.sh"
if [ -f "$common_script" ]; then . "$common_script"; else { echo "$common_script not found" >&2; exit 1; } fi

PROCESSES_TO_KILL="" # processes/kernel modules to kill and block

load_script_config

process_killer() {
    [ -z "$PROCESSES_TO_KILL" ] && { logecho "Error: PROCESSES_TO_KILL is not set" error; exit 1; }

    local _process _filepath _filewhich _filename _fileext _modulename

    for _process in $(echo "$PROCESSES_TO_KILL" | grep -o -e "[^ ]*"); do
        _filepath="$_process"

        if [ ! -f "$_filepath" ]; then
            _filewhich=$(which "$_process")
            [ -n "$_filewhich" ] && _filepath=$_filewhich
        fi

        [ -f "$_filepath" ] && mount | grep -Fq "$_filepath" && continue

        _filename="$(basename "$_filepath")"
        _fileext="${_filename##*.}"

        if [ "$_fileext" = "ko" ]; then
            _modulename="${_filename%.*}"
            _filepath="/lib/modules/$(uname -r)/$(modprobe -l "$_modulename")"

            if [ -f "$_filepath" ] && [ ! -h "$_filepath" ]; then
                lsmod | grep -Fq "$_modulename" && modprobe -r "$_modulename" && logecho "Blocked kernel module: $_process" alert && usleep 250000
                mount -o bind /dev/null "$_filepath"
            fi
        else
            [ -n "$(pidof "$_filename")" ] && killall "$_filename" && logecho "Killed process: $_process" alert

            if [ -f "$_filepath" ] && [ ! -h "$_filepath" ]; then
                usleep 250000
                mount -o bind /dev/null "$_filepath"
            fi
        fi
    done
}

case "$1" in
    "run")
        process_killer
    ;;
    "start")
        if [ -z "$IS_INTERACTIVE" ] && [ "$(awk -F '.' '{print $1}' /proc/uptime)" -lt 300 ]; then
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
