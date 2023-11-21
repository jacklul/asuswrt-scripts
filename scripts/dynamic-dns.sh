#!/bin/sh
# Made by Jack'lul <jacklul.github.io>
#
# Handle custom dynamic dns config
#
# Implements Custom DDNS feature from AsusWRT-Merlin:
#  https://github.com/RMerl/asuswrt-merlin.ng/wiki/DDNS-services
#

#shellcheck disable=SC2155

readonly SCRIPT_PATH="$(readlink -f "$0")"
readonly SCRIPT_NAME="$(basename "$SCRIPT_PATH" .sh)"
readonly SCRIPT_DIR="$(dirname "$SCRIPT_PATH")"
readonly SCRIPT_CONFIG="$SCRIPT_DIR/$SCRIPT_NAME.conf"
readonly SCRIPT_TAG="$(basename "$SCRIPT_PATH")"

CONFIG_FILE="/jffs/inadyn.conf" # Inadyn configuration file to use
CACHE_FILE="/tmp/last_wan_ip" # where to cache last public IP
IPECHO_URL="nvram" # "nvram" means use "nvram get wan0_ipaddr" (use "nvram2" for wan1), can use URL like "https://ipecho.net/plain" here or empty to not check
IPECHO_TIMEOUT=10 # maximum time in seconds to wait for loading IPECHO_URL address

if [ -f "$SCRIPT_CONFIG" ]; then
    #shellcheck disable=SC1090
    . "$SCRIPT_CONFIG"
fi

WAN_IP=""
LAST_WAN_IP=""
[ -f "$CACHE_FILE" ] && LAST_WAN_IP="$(cat "$CACHE_FILE")"
CURL_BINARY="curl"
[ -f /opt/bin/curl ] && CURL_BINARY="/opt/bin/curl"

run_ddns_update() {
    if inadyn --config="$CONFIG_FILE" --once --foreground; then
        logger -st "$SCRIPT_TAG" "Custom Dynamic DNS update successful"

        [ -n  "$WAN_IP" ] && echo "$WAN_IP" > "$CACHE_FILE"
    else
        logger -st "$SCRIPT_TAG" "Custom Dynamic DNS update failed"

        rm -f "$CACHE_FILE"
    fi
}

case "$1" in
    "run")
        { [ "$(nvram get wan0_state_t)" != "2" ] && [ "$(nvram get wan1_state_t)" != "2" ]; } && { echo "WAN network is not connected"; exit; }

        if [ "$IPECHO_URL" = "nvram" ]; then
            WAN_IP="$(nvram get wan0_ipaddr)"
        elif [ "$IPECHO_URL" = "nvram2" ]; then
            WAN_IP="$(nvram get wan1_ipaddr)"
        elif [ -n "$IPECHO_URL" ]; then
            WAN_IP="$($CURL_BINARY -fsL "$IPECHO_URL" -m "$IPECHO_TIMEOUT")"
        else
            FORCE=true
        fi

        if [ -n "$FORCE" ] || { [ -n "$WAN_IP" ] && [ "$WAN_IP" != "$LAST_WAN_IP" ]; }; then
            run_ddns_update
        fi
    ;;
    "force")
        run_ddns_update
    ;;
    "start")
        [ "$(uname -o)" = "ASUSWRT-Merlin" ] && logger -st "$SCRIPT_TAG" "Merlin firmware detected - you should probably use Custom DDNS or ddns-start script instead!"

        [ ! -f "$CONFIG_FILE" ] && { logger -st "$SCRIPT_TAG" "Unable to start - Inadyn config file ($CONFIG_FILE) not found"; exit 1; }
        inadyn -f "$CONFIG_FILE" --check-config > /dev/null || { logger -st "$SCRIPT_TAG" "Unable to start - Inadyn config is not valid"; exit 1; }

        if [ -x "$SCRIPT_DIR/cron-queue.sh" ]; then
            "$SCRIPT_DIR/cron-queue.sh" add "$SCRIPT_NAME" "$SCRIPT_PATH run"
        else
            cru a "$SCRIPT_NAME" "*/1 * * * * $SCRIPT_PATH run"
        fi
    ;;
    "stop")
        [ -x "$SCRIPT_DIR/cron-queue.sh" ] && "$SCRIPT_DIR/cron-queue.sh" remove "$SCRIPT_NAME"
        cru d "$SCRIPT_NAME"
    ;;
    "restart")
        sh "$SCRIPT_PATH" stop
        sh "$SCRIPT_PATH" start
    ;;
    *)
        echo "Usage: $0 run|start|stop|restart|force"
        exit 1
    ;;
esac
