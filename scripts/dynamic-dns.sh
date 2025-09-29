#!/bin/sh
# Made by Jack'lul <jacklul.github.io>
#
# Handle custom dynamic DNS configuration updates using Inadyn
#
# Implements Custom DDNS feature from Asuswrt-Merlin:
#  https://github.com/RMerl/asuswrt-merlin.ng/wiki/DDNS-services
#

#jas-update=dynamic-dns.sh
#shellcheck disable=SC2155
#shellcheck source=./common.sh
readonly common_script="$(dirname "$0")/common.sh"
if [ -f "$common_script" ]; then . "$common_script"; else { echo "$common_script not found" >&2; exit 1; } fi

CONFIG_FILE="/jffs/inadyn.conf" # Inadyn configuration file to use
IPECHO_URL="nvram" # "nvram" means use "nvram get wan0_ipaddr" (use "nvram2" for wan1), can use URL like "https://ipecho.net/plain" here or empty to not check
IPECHO_TIMEOUT=10 # maximum time in seconds to wait for loading IPECHO_URL address

load_script_config

[ -z "$IPECHO_TIMEOUT" ] && IPECHO_TIMEOUT=1 # this cannot be empty, set to the lowest possible value
state_file="$TMP_DIR/$script_name"
[ -f "$state_file" ] && last_wan_ip="$(cat "$state_file")"

run_ddns_update() {
    if inadyn --config="$CONFIG_FILE" --once --foreground; then
        logecho "Custom Dynamic DNS update successful" alert

        [ -n "$wan_ip" ] && echo "$wan_ip" > "$state_file"
    else
        logecho "Custom Dynamic DNS update failure"

        rm -f "$state_file"
    fi
}

check_and_run() {
    { [ "$(nvram get wan0_state_t)" != "2" ] && [ "$(nvram get wan1_state_t)" != "2" ] ; } && { echo "WAN network is not connected" >&2; return 1; }
    [ -z "$CONFIG_FILE" ] && { logecho "Error: CONFIG_FILE is not set" error; exit 1; }
    [ -z "$IPECHO_URL" ] && { logecho "Error: IPECHO_URL is not set" error; exit 1; }
    [ ! -f "$CONFIG_FILE" ] && { logecho "Error: Inadyn config file '$CONFIG_FILE' not found" error; exit 1; }
    inadyn -f "$CONFIG_FILE" --check-config > /dev/null || { logecho "Error: Inadyn config is not valid" error; exit 1; }

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
        check_and_run
        crontab_entry add "*/1 * * * * $script_path run"
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
