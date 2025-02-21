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

readonly SCRIPT_PATH="$(readlink -f "$0")"
readonly SCRIPT_NAME="$(basename "$SCRIPT_PATH" .sh)"
readonly SCRIPT_DIR="$(dirname "$SCRIPT_PATH")"
readonly SCRIPT_CONFIG="$SCRIPT_DIR/$SCRIPT_NAME.conf"
readonly SCRIPT_TAG="$(basename "$SCRIPT_PATH")"

ROTATE_WL="wl0.1 wl1.1" # guest network interfaces to randomize passwords for (find them using 'nvram show | grep "^wl[0-9]\.[0-9]_ssid"' command), separated by space
CHAR_LIST="ABCDEFGHIJKLMNPQRSTUVWXYZabcdefghijklmnpqrstuvwxyz123456789" # characters list for generated passwords
PASSWORD_LENGTH=20 # length of generated passwords
ROTATE_ON_START=false # should we rotate passwords on script start
CRON="0 4 * * *"

if [ -f "$SCRIPT_CONFIG" ]; then
    #shellcheck disable=SC1090
    . "$SCRIPT_CONFIG"
fi

get_random_password() {
    #shellcheck disable=SC2002
    cat /dev/urandom | env LC_CTYPE=C tr -dc "$CHAR_LIST" | head -c $PASSWORD_LENGTH; echo;
}

case "$1" in
    "run")
        for INTERFACE in $ROTATE_WL; do
            SSID="$(nvram get "${INTERFACE}_ssid")"

            if [ -n "$SSID" ]; then
                if [ "$(nvram get "${INTERFACE}_bss_enabled")" = "1" ]; then
                    logger -st "$SCRIPT_TAG" "Rotating password for Guest WiFi: $SSID"

                    NEW_PASSWORD="$(get_random_password)"
                    nvram set "${INTERFACE}_wpa_psk"="$NEW_PASSWORD"

                    CHANGED=1
                fi
            else
                logger -st "$SCRIPT_TAG" "Invalid guest network interface: $INTERFACE"
            fi
        done

        [ -n "$CHANGED" ] && nvram commit && service restart_wireless
    ;;
    "start")
        [ -z "$ROTATE_WL" ] && { logger -st "$SCRIPT_TAG" "Unable to start - no guest networks to rotate password for are set"; exit 1; }

        cru a "$SCRIPT_NAME" "$CRON $SCRIPT_PATH run"

        if [ "$ROTATE_ON_START" = true ]; then
            if [ "$(awk -F '.' '{print $1}' /proc/uptime)" -lt "300" ]; then
                { sleep 60 && sh "$SCRIPT_PATH" run; } & # delay when freshly booted
            else
                sh "$SCRIPT_PATH" run
            fi
        fi
    ;;
    "stop")
        cru d "$SCRIPT_NAME"
    ;;
    "restart")
        sh "$SCRIPT_PATH" stop
        sh "$SCRIPT_PATH" start
    ;;
    *)
        echo "Usage: $0 run|start|stop|restart"
        exit 1
    ;;
esac
