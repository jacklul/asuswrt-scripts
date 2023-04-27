#!/bin/sh
# Made by Jack'lul <jacklul.github.io>
#
# Send warning to syslog when temperatures reaches specific threshold
#

#shellcheck disable=SC2155

TEMPERATURE_TARGET="80" # target temperature at which send the warning
COOLDOWN=300 # how long to wait (seconds) before sending another warning
CACHE_FILE="/tmp/last_temperature_warning" # where to cache last warning uptime value
CRON_MINUTE="*/1"
CRON_HOUR="*"

# This means that this is a Merlin firmware
if [ -f "/usr/sbin/helper.sh" ]; then
    #shellcheck disable=SC1091
    . /usr/sbin/helper.sh

    TEMPERATURE_TARGET_=$(am_settings_get jl_twarning_ttarget)
    COOLDOWN_=$(am_settings_get jl_twarning_cooldown)

    [ -n "$TEMPERATURE_TARGET_" ] && TEMPERATURE_TARGET=$TEMPERATURE_TARGET_
    [ -n "$COOLDOWN_" ] && COOLDOWN=$COOLDOWN_
fi

readonly SCRIPT_NAME="$(basename "$0" .sh)"
readonly SCRIPT_PATH="$(readlink -f "$0")"
readonly SCRIPT_CONFIG="$(dirname "$0")/$SCRIPT_NAME.conf"
if [ -f "$SCRIPT_CONFIG" ]; then
    #shellcheck disable=SC1090
    . "$SCRIPT_CONFIG"
fi

get_temperatures() {
    ETH_24G=""
    ETH_5G=""

    for _INTERFACE in /sys/class/net/eth*; do
        [ ! -d "$_INTERFACE" ] && continue

        _INTERFACE="$(basename "$_INTERFACE")"
        _STATUS="$(wl -i "$_INTERFACE" status 2>/dev/null)"

        if echo "$_STATUS" | grep -q "2.4GHz"; then
            ETH_24G="$_INTERFACE"
        elif echo "$_STATUS" | grep -q "5GHz"; then
            ETH_5G="$_INTERFACE"
        fi

        [ -n "$ETH_24G" ] && [ -n "$ETH_5G" ] && break
    done

    [ -f "/sys/class/thermal/thermal_zone0/temp" ] && CPU_TEMPERATURE="$(awk '{print $1 / 1000}' < /sys/class/thermal/thermal_zone0/temp)"
    [ -n "$ETH_24G" ] && WIFI_24G_TEMPERATURE="$(wl -i "$ETH_24G" phy_tempsense | awk '{print $1 / 2 + 20}')"
    [ -n "$ETH_5G" ] && WIFI_5G_TEMPERATURE="$(wl -i "$ETH_5G" phy_tempsense | awk '{print $1 / 2 + 20}')"
}

case "$1" in
    "run")
        UPTIME="$(awk -F '.' '{print $1}' /proc/uptime)"
        UPTIME_CACHED="$([ -f "$CACHE_FILE" ] && cat "$CACHE_FILE" || echo "0")"

        if [ -z "$UPTIME_CACHED" ] || [ "$((UPTIME_CACHED+COOLDOWN))" -le "$UPTIME" ]; then
            get_temperatures

            if [ "$(printf "%.0f" "$CPU_TEMPERATURE")" -ge "$TEMPERATURE_TARGET" ]; then
                logger -s -t "$SCRIPT_NAME" "CPU temperature warning: $CPU_TEMPERATURE C"
                WARNING=1
            fi

            if [ -n "$WIFI_24G_TEMPERATURE" ] && [ "$(printf "%.0f\n" "$WIFI_24G_TEMPERATURE")" -ge "$TEMPERATURE_TARGET" ]; then
                logger -s -t "$SCRIPT_NAME" "WiFi 2.4G temperature warning: $WIFI_24G_TEMPERATURE C"
                WARNING=1
            fi

            if [ -n "$WIFI_5G_TEMPERATURE" ] && [ "$(printf "%.0f\n" "$WIFI_5G_TEMPERATURE")" -ge "$TEMPERATURE_TARGET" ]; then
                logger -s -t "$SCRIPT_NAME" "WiFi 5G temperature warning: $WIFI_5G_TEMPERATURE C"
                WARNING=1
            fi

            [ -n "$WARNING" ] && echo "$UPTIME" > "$CACHE_FILE"
        fi
    ;;
    "check")
        get_temperatures

        [ -n "$CPU_TEMPERATURE" ] && echo "CPU temperature: $CPU_TEMPERATURE C"
        [ -n "$WIFI_24G_TEMPERATURE" ] && echo "WiFi 2.4G temperature: $WIFI_24G_TEMPERATURE C ($ETH_24G)"
        [ -n "$WIFI_5G_TEMPERATURE" ] && echo "WiFi 5G temperature: $WIFI_5G_TEMPERATURE C ($ETH_5G)"
    ;;
    "start")
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
        echo "Usage: $0 run|start|stop|restart|check"
        exit 1
    ;;
esac
