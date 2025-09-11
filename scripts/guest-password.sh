#!/bin/sh
# Made by Jack'lul <jacklul.github.io>
#
# Randomize Guest WiFi passwords
#
# Based on:
#  https://github.com/RMerl/asuswrt-merlin.ng/wiki/Guest-WIFI-QR-code-generator-for-display-on-local-network-webpage-(visible-from-TV,-smartphones...)-and-random-password-rotation
#

#jas-update=guest-password.sh
#shellcheck disable=SC2155
#shellcheck source=./common.sh
readonly common_script="$(dirname "$0")/common.sh"
if [ -f "$common_script" ]; then . "$common_script"; else { echo "$common_script not found"; exit 1; } fi

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
    [ -z "$WL_INTERFACES" ] && { logecho "Error: WL_INTERFACES is not set"; exit 1; }
    [ -z "$CHARACTER_LIST" ] && { logecho "Error: CHARACTER_LIST is not set"; exit 1; }
    [ -z "$PASSWORD_LENGTH" ] && { logecho "Error: PASSWORD_LENGTH is not set"; exit 1; }

    for interface in $WL_INTERFACES; do
        ssid="$(nvram get "${interface}_ssid")"

        if [ -n "$ssid" ]; then
            if [ "$(nvram get "${interface}_bss_enabled")" = "1" ]; then
                logecho "Rotating password for guest WiFi: $ssid" true

                new_password="$(get_random_password)"
                nvram set "${interface}_wpa_psk"="$new_password"

                changed=1
                [ "$(nvram get "${interface}_bss_enabled")" = "1" ] && restart=1
            fi
        else
            logecho "Invalid guest network: $interface"
        fi
    done

    [ -n "$changed" ] && nvram commit
    [ -n "$restart" ] && service restart_wireless
}

case "$1" in
    "run")
        rotate_passwords
    ;;
    "start")
        [ -n "$CRON" ] && crontab_entry add "$CRON $script_path run"

        if [ "$ROTATE_ON_START" = true ]; then
            if [ ! -t 0 ] && [ "$(awk -F '.' '{print $1}' /proc/uptime)" -lt 300 ]; then
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
