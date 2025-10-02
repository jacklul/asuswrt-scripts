#!/bin/sh
# Made by Jack'lul <jacklul.github.io>
#
# Ensure that WPS is disabled on the router
#
# Based on:
#  https://www.snbforums.com/threads/asus-rt-ac87u-stepped-into-the-382-branch-d.44227/#post-376642
#

#jas-update=disable-wps.sh
#shellcheck shell=ash
#shellcheck disable=SC2155

#shellcheck source=./common.sh
readonly common_script="$(dirname "$0")/common.sh"
if [ -f "$common_script" ]; then . "$common_script"; else { echo "$common_script not found" >&2; exit 1; } fi

CRON="0 0 * * *" # schedule as cron string

load_script_config

disable_wps() {
    [ "$(nvram get wps_enable)" != "0" ] && nvram set wps_enable=0 && _changed=1
    [ "$(nvram get wps_enable_x)" != "0" ] && nvram set wps_enable_x=0 && _changed=1

    local _wps_mode_not_disabled="$(nvram show 2>/dev/null | grep "_wps_mode" | grep -v "=disabled" | cut -d '=' -f 1)"
    local _variable _value _changed

    IFS="$(printf '\n\b')"
    for _variable in $_wps_mode_not_disabled; do
        _value="$(nvram get "$_variable")"

        if [ -n "$_value" ] && [ "$_value" != "disabled" ]; then
            nvram set "$_variable=disabled"
            _changed=1
        fi
    done

    if [ -n "$_changed" ]; then
        nvram commit
        service restart_wireless

        logecho "WPS has been disabled" alert
    fi
}

case "$1" in
    "run")
        disable_wps
    ;;
    "start")
        [ -n "$CRON" ] && crontab_entry add "$CRON $script_path run"

        if [ -z "$IS_INTERACTIVE" ] && [ "$(awk -F '.' '{print $1}' /proc/uptime)" -lt 300 ]; then
            { sleep 60 && disable_wps; } & # delay when freshly booted
        else
            disable_wps
        fi
    ;;
    "stop")
        crontab_entry delete
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
