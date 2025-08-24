#!/bin/sh
# Made by Jack'lul <jacklul.github.io>
#
# Handle custom dynamic dns config
#
# Implements Custom DDNS feature from Asuswrt-Merlin:
#  https://github.com/RMerl/asuswrt-merlin.ng/wiki/DDNS-services
#

#jacklul-asuswrt-scripts-update=dynamic-dns.sh
#shellcheck disable=SC2155

readonly script_path="$(readlink -f "$0")"
readonly script_name="$(basename "$script_path" .sh)"
readonly script_dir="$(dirname "$script_path")"
readonly script_config="$script_dir/$script_name.conf"

CONFIG_FILE="/jffs/inadyn.conf" # Inadyn configuration file to use
CACHE_FILE="/tmp/last_wan_ip" # where to cache last public IP
IPECHO_URL="nvram" # "nvram" means use "nvram get wan0_ipaddr" (use "nvram2" for wan1), can use URL like "https://ipecho.net/plain" here or empty to not check
IPECHO_TIMEOUT=10 # maximum time in seconds to wait for loading IPECHO_URL address

umask 022 # set default umask

if [ -f "$script_config" ]; then
    #shellcheck disable=SC1090
    . "$script_config"
fi

is_merlin_firmware() { #ISMERLINFIRMWARE_START#
    if [ -f "/usr/sbin/helper.sh" ]; then
        return 0
    fi
    return 1
} #ISMERLINFIRMWARE_END#

is_merlin_firmware && merlin=true
wan_ip=""
last_wan_ip=""
[ -f "$CACHE_FILE" ] && last_wan_ip="$(cat "$CACHE_FILE")"
curl_binary="curl"
[ -f /opt/bin/curl ] && curl_binary="/opt/bin/curl" # prefer Entware's curl as it is not modified by Asus

run_ddns_update() {
    if inadyn --config="$CONFIG_FILE" --once --foreground; then
        logger -st "$script_name" "Custom Dynamic DNS update successful"

        [ -n  "$wan_ip" ] && echo "$wan_ip" > "$CACHE_FILE"
    else
        logger -st "$script_name" "Custom Dynamic DNS update failed"

        rm -f "$CACHE_FILE"
    fi
}

case "$1" in
    "run")
        { [ "$(nvram get wan0_state_t)" != "2" ] && [ "$(nvram get wan1_state_t)" != "2" ] ; } && { echo "WAN network is not connected"; exit 1; }

        if [ "$IPECHO_URL" = "nvram" ]; then
            wan_ip="$(nvram get wan0_ipaddr)"
        elif [ "$IPECHO_URL" = "nvram2" ]; then
            wan_ip="$(nvram get wan1_ipaddr)"
        elif [ -n "$IPECHO_URL" ]; then
            wan_ip="$($curl_binary -fsL "$IPECHO_URL" -m "$IPECHO_TIMEOUT")"
        else
            force=true
        fi

        if [ -n "$force" ] || { [ -n "$wan_ip" ] && [ "$wan_ip" != "$last_wan_ip" ] ; }; then
            run_ddns_update
        fi
    ;;
    "force")
        run_ddns_update
    ;;
    "start")
        [ -n "$merlin" ] && logger -st "$script_name" "Asuswrt-Merlin firmware detected - you should probably use Custom DDNS or 'ddns-start' script instead!"

        [ ! -f "$CONFIG_FILE" ] && { logger -st "$script_name" "Error: Unable to start - Inadyn config file ('$CONFIG_FILE') not found"; exit 1; }
        inadyn -f "$CONFIG_FILE" --check-config > /dev/null || { logger -st "$script_name" "Error: Unable to start - Inadyn config is not valid"; exit 1; }

        if [ -x "$script_dir/cron-queue.sh" ]; then
            sh "$script_dir/cron-queue.sh" add "$script_name" "$script_path run"
        else
            cru a "$script_name" "*/1 * * * * $script_path run"
        fi
    ;;
    "stop")
        [ -x "$script_dir/cron-queue.sh" ] && sh "$script_dir/cron-queue.sh" remove "$script_name"
        cru d "$script_name"
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
