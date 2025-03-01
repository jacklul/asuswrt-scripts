#!/bin/sh
# Made by Jack'lul <jacklul.github.io>
#
# Randomize Guest WiFi passwords
#
# Based on:
#  https://github.com/RMerl/asuswrt-merlin.ng/wiki/Guest-WIFI-QR-code-generator-for-display-on-local-network-webpage-(visible-from-TV,-smartphones...)-and-random-password-rotation
#

#jacklul-asuswrt-scripts-update=guest-password.sh
#shellcheck disable=SC2155

readonly script_path="$(readlink -f "$0")"
readonly script_name="$(basename "$script_path" .sh)"
readonly script_dir="$(dirname "$script_path")"
readonly script_config="$script_dir/$script_name.conf"

ROTATE_WL="wl0.1 wl1.1" # guest network interfaces to randomize passwords for (find them using 'nvram show | grep "^wl[0-9]\.[0-9]_ssid"' command), separated by space
CHAR_LIST="ABCDEFGHIJKLMNPQRSTUVWXYZabcdefghijklmnpqrstuvwxyz123456789" # characters list for generated passwords
PASSWORD_LENGTH=20 # length of generated passwords
ROTATE_ON_START=false # should we rotate passwords on script start
CRON="0 4 * * *" # schedule as cron string

if [ -f "$script_config" ]; then
    #shellcheck disable=SC1090
    . "$script_config"
fi

get_random_password() {
    #shellcheck disable=SC2002
    cat /dev/urandom | env LC_CTYPE=C tr -dc "$CHAR_LIST" | head -c $PASSWORD_LENGTH; echo;
}

case "$1" in
    "run")
        for interface in $ROTATE_WL; do
            ssid="$(nvram get "${interface}_ssid")"

            if [ -n "$ssid" ]; then
                if [ "$(nvram get "${interface}_bss_enabled")" = "1" ]; then
                    logger -st "$script_name" "Rotating password for Guest WiFi: $ssid"

                    new_password="$(get_random_password)"
                    nvram set "${interface}_wpa_psk"="$new_password"

                    changed=1
                fi
            else
                logger -st "$script_name" "Invalid guest network interface: $interface"
            fi
        done

        [ -n "$changed" ] && nvram commit && service restart_wireless
    ;;
    "start")
        [ -z "$ROTATE_WL" ] && { logger -st "$script_name" "Unable to start - no guest networks to rotate password for are set"; exit 1; }

        cru a "$script_name" "$CRON $script_path run"

        if [ "$ROTATE_ON_START" = true ]; then
            if [ "$(awk -F '.' '{print $1}' /proc/uptime)" -lt 300 ]; then
                { sleep 60 && sh "$script_path" run; } & # delay when freshly booted
            else
                sh "$script_path" run
            fi
        fi
    ;;
    "stop")
        cru d "$script_name"
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
