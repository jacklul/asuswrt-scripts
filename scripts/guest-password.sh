#!/bin/sh
# Made by Jack'lul <jacklul.github.io>
#
# Randomize Guest WiFi passwords
#
# Based on:
#  https://github.com/RMerl/asuswrt-merlin.ng/wiki/Guest-WIFI-QR-code-generator-for-display-on-local-network-webpage-(visible-from-TV,-smartphones...)-and-random-password-rotation
#

#jas-update=guest-password.sh
#shellcheck shell=ash
#shellcheck disable=SC2155

#shellcheck source=./common.sh
readonly common_script="$(dirname "$0")/common.sh"
if [ -f "$common_script" ]; then . "$common_script"; else { echo "$common_script not found" >&2; exit 1; } fi

WL_INTERFACES="wl0.1 wl1.1" # guest network interfaces to randomize passwords for (find them using 'nvram show | grep "^wl[0-9]\.[0-9]_ssid"' command), separated by space
CHARACTER_LIST="ABCDEFGHIJKLMNPQRSTUVWXYZabcdefghijklmnpqrstuvwxyz123456789" # characters list for generated passwords
PASSWORD_LENGTH=20 # length of generated passwords
ROTATE_ON_START=false # should we rotate passwords on script start
CRON="0 4 * * *" # schedule as cron string

load_script_config

get_random_password() {
    #shellcheck disable=SC2002
    cat /dev/urandom | env LC_CTYPE=C tr -dc "$CHARACTER_LIST" | head -c $PASSWORD_LENGTH; echo;
}

rotate_passwords() {
    [ -z "$WL_INTERFACES" ] && { logecho "Error: WL_INTERFACES is not set" error; exit 1; }
    [ -z "$CHARACTER_LIST" ] && { logecho "Error: CHARACTER_LIST is not set" error; exit 1; }
    [ -z "$PASSWORD_LENGTH" ] && { logecho "Error: PASSWORD_LENGTH is not set" error; exit 1; }

    local _interface _ssid _new_password _changed _restart

    for _interface in $WL_INTERFACES; do
        _ssid="$(nvram get "${_interface}_ssid")"

        if [ -n "$_ssid" ]; then
            if [ "$(nvram get "${_interface}_bss_enabled")" = "1" ]; then
                logecho "Rotating password for guest WiFi: $_ssid" alert

                _new_password="$(get_random_password)"
                nvram set "${_interface}_wpa_psk"="$_new_password"

                _changed=1
                [ "$(nvram get "${_interface}_bss_enabled")" = "1" ] && _restart=1
            fi
        else
            logecho "Invalid guest network: $_interface" error
        fi
    done

    [ -n "$_changed" ] && nvram commit
    [ -n "$_restart" ] && service restart_wireless
}

case "$1" in
    "run")
        rotate_passwords
    ;;
    "start")
        [ -n "$CRON" ] && crontab_entry add "$CRON $script_path run"

        if [ "$ROTATE_ON_START" = true ]; then
            if [ -z "$IS_INTERACTIVE" ] && [ "$(awk -F '.' '{print $1}' /proc/uptime)" -lt 300 ]; then
                { sleep 60 && rotate_passwords; } & # delay when freshly booted
            else
                rotate_passwords
            fi
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
