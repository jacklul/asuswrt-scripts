#!/bin/sh
# Made by Jack'lul <jacklul.github.io>
#
# Randomize Guest WiFi passwords and generate HTML pages for them
#
# Pages will be available at www.asusrouter.com/user/guest-INTERFACE.html and www.asusrouter.com/user/guest-list.html
#
# Based on:
#  https://github.com/RMerl/asuswrt-merlin.ng/wiki/Guest-WIFI-QR-code-generator-for-display-on-local-network-webpage-(visible-from-TV,-smartphones...)-and-random-password-rotation
#

#shellcheck disable=SC2155

readonly SCRIPT_PATH="$(readlink -f "$0")"
readonly SCRIPT_NAME="$(basename "$SCRIPT_PATH" .sh)"
readonly SCRIPT_DIR="$(dirname "$SCRIPT_PATH")"
readonly SCRIPT_CONFIG="$SCRIPT_DIR/$SCRIPT_NAME.conf"
readonly SCRIPT_TAG="$(basename "$SCRIPT_PATH")"

HTML_WL="wl0.1 wl0.2 wl0.3 wl1.1 wl1.2 wl1.3 wl2.1 wl2.2 wl2.3 wl3.1 wl3.2 wl3.3" # list of guest network interfaces to generate HTML pages for, separated by space
ROTATE_WL="wl0.1 wl1.1" # guest network interfaces to randomize passwords for (find them using 'nvram show | grep "^wl[0-9]\.[0-9]_ssid"' command), separated by space
CHAR_LIST="ABCDEFGHIJKLMNPQRSTUVWXYZabcdefghijklmnpqrstuvwxyz123456789" # characters list for generated passwords
PASSWORD_LENGTH=20 # length of generated passwords
ROTATE_ON_START=false # should we rotate passwords on script start
HTML_FILE="$SCRIPT_DIR/$SCRIPT_NAME.html" # base html file, "#INTERFACE#" string is replaced with interface name
CRON="0 4 * * *"

if [ -f "$SCRIPT_CONFIG" ]; then
    #shellcheck disable=SC1090
    . "$SCRIPT_CONFIG"
fi

{ [ "$ROTATE_ON_START" = "true" ] || [ "$ROTATE_ON_START" = true ]; } && ROTATE_ON_START="1" || ROTATE_ON_START="0"

get_random_password() {
    #shellcheck disable=SC2002
    cat /dev/urandom | env LC_CTYPE=C tr -dc "$CHAR_LIST" | head -c $PASSWORD_LENGTH; echo;
}

generate_html_pages() {
    if [ -f "$HTML_FILE" ]; then
        LIST_HTML="/www/user/guest-list.html"
        echo "<ul style=\"font-size:14pt;list-style: none;margin:0;padding:0;\">" > "$LIST_HTML"

        for INTERFACE in $HTML_WL; do
            SSID="$(nvram get "${INTERFACE}_ssid")"

            if [ -n "$SSID" ]; then
                cp "$HTML_FILE" "/www/user/guest-$INTERFACE.html"
                sed -i "s/#INTERFACE#/$INTERFACE/g" "/www/user/guest-$INTERFACE.html"

                echo "<li><a href=\"/user/guest-$INTERFACE.html\">$INTERFACE - $SSID</a></li>" >> "$LIST_HTML"
            fi
        done
        echo "</ul>" >> "$LIST_HTML"
    else
        logger -s -t "$SCRIPT_TAG" "Not generating HTML pages because '$HTML_FILE' does not exist"
    fi
}

case "$1" in
    "run")
        for INTERFACE in $ROTATE_WL; do
            SSID="$(nvram get "${INTERFACE}_ssid")"

            if [ -n "$SSID" ]; then
                if [ "$(nvram get "${INTERFACE}_bss_enabled")" = "1" ]; then
                    logger -s -t "$SCRIPT_TAG" "Rotating password for Guest WiFi: $SSID"

                    NEW_PASSWORD="$(get_random_password)"
                    nvram set "${INTERFACE}_wpa_psk"="$NEW_PASSWORD"

                    CHANGED=1
                fi
            else
                logger -s -t "$SCRIPT_TAG" "Invalid guest network interface: $INTERFACE"
            fi
        done

        [ -n "$CHANGED" ] && nvram commit && service restart_wireless

        generate_html_pages
    ;;
    "html")
        generate_html_pages
    ;;
    "start")
        [ -n "$ROTATE_WL" ] && cru a "$SCRIPT_NAME" "$CRON $SCRIPT_PATH run"

        if [ "$ROTATE_ON_START" = "1" ]; then
            if [ "$(awk -F '.' '{print $1}' /proc/uptime)" -lt "300" ]; then
                { sleep 60 && sh "$SCRIPT_PATH" run; } & # delay when freshly booted
            else
                sh "$SCRIPT_PATH" run
            fi
        else
            generate_html_pages
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
        echo "Usage: $0 run|start|stop|restart|html"
        exit 1
    ;;
esac
