#!/bin/sh
# Made by Jack'lul <jacklul.github.io>
#
# Handle custom dynamic dns config
#
# Implements Custom DDNS feature from Asuswrt-Merlin:
#  https://github.com/RMerl/asuswrt-merlin.ng/wiki/DDNS-services
#

#jas-update=dynamic-dns.sh
#shellcheck disable=SC2155
#shellcheck source=./common.sh
readonly common_script="$(dirname "$0")/common.sh"
if [ -f "$common_script" ]; then . "$common_script"; else { echo "$common_script not found"; exit 1; } fi

CONFIG_FILE="/jffs/inadyn.conf" # Inadyn configuration file to use
CACHE_FILE="$TMP_DIR/$script_name" # where to cache last public IP
IPECHO_URL="nvram" # "nvram" means use "nvram get wan0_ipaddr" (use "nvram2" for wan1), can use URL like "https://ipecho.net/plain" here or empty to not check
IPECHO_TIMEOUT=10 # maximum time in seconds to wait for loading IPECHO_URL address

load_script_config

wan_ip=""
last_wan_ip=""
[ -f "$CACHE_FILE" ] && last_wan_ip="$(cat "$CACHE_FILE")"

run_ddns_update() {
    if inadyn --config="$CONFIG_FILE" --once --foreground; then
        logger -st "$script_name" "Custom Dynamic DNS update successful"

        [ -n  "$wan_ip" ] && echo "$wan_ip" > "$CACHE_FILE"
    else
        logger -st "$script_name" "Custom Dynamic DNS update failed"

        rm -f "$CACHE_FILE"
    fi
}

check_and_run() {
    { [ "$(nvram get wan0_state_t)" != "2" ] && [ "$(nvram get wan1_state_t)" != "2" ] ; } && { echo "WAN network is not connected"; exit 1; }

    if [ "$IPECHO_URL" = "nvram" ]; then
        wan_ip="$(nvram get wan0_ipaddr)"
    elif [ "$IPECHO_URL" = "nvram2" ]; then
        wan_ip="$(nvram get wan1_ipaddr)"
    elif [ -n "$IPECHO_URL" ]; then
        wan_ip="$(fetch "$IPECHO_URL" "" "$IPECHO_TIMEOUT")"
    else
        force=true
    fi

    if [ -n "$force" ] || { [ -n "$wan_ip" ] && [ "$wan_ip" != "$last_wan_ip" ] ; }; then
        run_ddns_update
    fi
}

case "$1" in
    "run")
        check_and_run
    ;;
    "force")
        run_ddns_update
    ;;
    "start")
        [ ! -f "$CONFIG_FILE" ] && { logger -st "$script_name" "Unable to start - Inadyn config file ('$CONFIG_FILE') not found"; exit 1; }
        inadyn -f "$CONFIG_FILE" --check-config > /dev/null || { logger -st "$script_name" "Unable to start - Inadyn config is not valid"; exit 1; }
        crontab_entry add "*/1 * * * * $script_path run"
        check_and_run
    ;;
    "stop")
        crontab_entry delete
    ;;
    "restart")
        sh "$script_path" stop
        sh "$script_path" start
    ;;
    *)
        echo "Usage: $0 run|start|stop|restart|force"
        exit 1
    ;;
esac
