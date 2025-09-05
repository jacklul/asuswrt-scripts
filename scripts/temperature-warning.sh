#!/bin/sh
# Made by Jack'lul <jacklul.github.io>
#
# Send warning to syslog when temperatures reaches specific threshold
#

#jas-update=temperature-warning.sh
#shellcheck disable=SC2155
#shellcheck source=./common.sh
readonly common_script="$(dirname "$0")/common.sh"
if [ -f "$common_script" ]; then . "$common_script"; else { echo "$common_script not found"; exit 1; } fi

TEMPERATURE_TARGET=80 # target temperature at which log the warning
COOLDOWN=300 # how long to wait (seconds) before logging another warning
CACHE_FILE="$TMP_DIR/$script_name" # where to cache last warning uptime value

load_script_config

get_temperatures() {
    _eth_24g=""
    _eth_5g=""

    for _interface in /sys/class/net/eth*; do
        [ ! -d "$_interface" ] && continue

        _interface="$(basename "$_interface")"
        _status="$(wl -i "$_interface" status 2> /dev/null)"

        if echo "$_status" | grep -Fq "2.4GHz"; then
            _eth_24g="$_interface"
        elif echo "$_status" | grep -Fq "5GHz"; then
            _eth_5g="$_interface"
        fi

        [ -n "$_eth_24g" ] && [ -n "$_eth_5g" ] && break
    done

    [ -f /sys/class/thermal/thermal_zone0/temp ] && cpu_temperature="$(awk '{print $1 / 1000}' < /sys/class/thermal/thermal_zone0/temp)"
    [ -n "$_eth_24g" ] && wifi_24g_temperature="$(wl -i "$_eth_24g" phy_tempsense | awk '{print $1 / 2 + 20}')"
    [ -n "$_eth_5g" ] && wifi_5g_temperature="$(wl -i "$_eth_5g" phy_tempsense | awk '{print $1 / 2 + 20}')"
}

case "$1" in
    "run")
        uptime="$(awk -F '.' '{print $1}' /proc/uptime)"
        uptime_cached="$([ -f "$CACHE_FILE" ] && cat "$CACHE_FILE" || echo "0")"

        if [ -z "$uptime_cached" ] || [ "$((uptime_cached+COOLDOWN))" -le "$uptime" ]; then
            get_temperatures

            if [ "$(printf "%.0f" "$cpu_temperature")" -ge "$TEMPERATURE_TARGET" ]; then
                logger -st "$script_name" "CPU temperature warning: $cpu_temperature C"
                warning=1
            fi

            if [ -n "$wifi_24g_temperature" ] && [ "$(printf "%.0f\n" "$wifi_24g_temperature")" -ge "$TEMPERATURE_TARGET" ]; then
                logger -st "$script_name" "WiFi 2.4G temperature warning: $wifi_24g_temperature C"
                warning=1
            fi

            if [ -n "$wifi_5g_temperature" ] && [ "$(printf "%.0f\n" "$wifi_5g_temperature")" -ge "$TEMPERATURE_TARGET" ]; then
                logger -st "$script_name" "WiFi 5G temperature warning: $wifi_5g_temperature C"
                warning=1
            fi

            [ -n "$warning" ] && echo "$uptime" > "$CACHE_FILE"
        fi
    ;;
    "check")
        get_temperatures

        [ -n "$cpu_temperature" ] && echo "CPU temperature: $cpu_temperature C"
        [ -n "$wifi_24g_temperature" ] && echo "WiFi 2.4G temperature: $wifi_24g_temperature C ($_eth_24g)"
        [ -n "$wifi_5g_temperature" ] && echo "WiFi 5G temperature: $wifi_5g_temperature C ($_eth_5g)"
    ;;
    "start")
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
        echo "Usage: $0 run|start|stop|restart|check"
        exit 1
    ;;
esac
