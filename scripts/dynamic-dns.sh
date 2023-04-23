#!/bin/sh
# Made by Jack'lul <jacklul.github.io>
#
# Handle custom dynamic dns config
#
# Implements Custom DDNS feature from AsusWRT-Merlin:
#  https://github.com/RMerl/asuswrt-merlin.ng/wiki/DDNS-services
#

#shellcheck disable=SC2155

CONFIG_FILE="/jffs/inadyn.conf" # Inadyn configuration file to use
CACHE_FILE="/tmp/last_wan_ip" # where to cache last public IP
IPECHO_URL="nvram" # "nvram" means use "nvram get wan0_ipaddr", can use URL like "https://ipecho.net/plain" here or empty to not check
IPECHO_TIMEOUT=10 # maximum time in seconds to wait for loading IPECHO_URL address
CRON_MINUTE="*/1"
CRON_HOUR="*"

readonly SCRIPT_NAME="$(basename "$0" .sh)"
readonly SCRIPT_PATH="$(readlink -f "$0")"
readonly SCRIPT_CONFIG="$(dirname "$0")/$SCRIPT_NAME.conf"
if [ -f "$SCRIPT_CONFIG" ]; then
    #shellcheck disable=SC1090
    . "$SCRIPT_CONFIG"
fi

WAN_IP=""
LAST_WAN_IP=""
[ -f "$CACHE_FILE" ] && LAST_WAN_IP="$(cat "$CACHE_FILE")"

case "$1" in
    "run")
        { [ "$(nvram get wan0_state_t)" != "2" ] && [ "$(nvram get wan1_state_t)" != "2" ]; } && { echo "WAN network is not connected"; exit 1; }

        if [ "$IPECHO_URL" = "nvram" ]; then
            WAN_IP="$(nvram get wan0_ipaddr)"
        elif [ -n "$IPECHO_URL" ]; then
            WAN_IP="$(curl --insecure "$IPECHO_URL" --max-time "$IPECHO_TIMEOUT")"
        else
            FORCE=true
        fi

        if [ -n "$FORCE" ] || { [ -n "$WAN_IP" ] && [ "$WAN_IP" != "$LAST_WAN_IP" ]; }; then
            if inadyn -f "$CONFIG_FILE" --once --foreground; then
                logger -s -t "$SCRIPT_NAME" "Custom Dynamic DNS update successful"

                [ -n  "$WAN_IP" ] && echo "$WAN_IP" > "$CACHE_FILE"
            else
                logger -s -t "$SCRIPT_NAME" "Custom Dynamic DNS update failed"

                rm -f "$CACHE_FILE"
            fi
        fi
    ;;
    "start")
        [ -f "/usr/sbin/helper.sh" ] && logger -s -t "$SCRIPT_NAME" "Merlin firmware detected - you should probably use Custom DDNS or ddns-start script instead!"

        [ ! -f "$CONFIG_FILE" ] && { logger -s -t "$SCRIPT_NAME" "Unable to start - Inadyn config file ($CONFIG_FILE) not found"; exit 1; }
        inadyn -f "$CONFIG_FILE" --check-config >/dev/null || { logger -s -t "$SCRIPT_NAME" "Unable to start - Inadyn config is not valid"; exit 1; }

        cru a "$SCRIPT_NAME" "$CRON_MINUTE $CRON_HOUR * * * $SCRIPT_PATH run"
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
