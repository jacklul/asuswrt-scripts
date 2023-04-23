#!/bin/sh
# Made by Jack'lul <jacklul.github.io>
#
# Automatically turns LEDs on/off on by schedule
#
# Based on:
#  https://github.com/RMerl/asuswrt-merlin.ng/wiki/Scheduled-LED-control
#  https://github.com/decoderman/amtm/blob/master/amtm_modules/led_control.mod
#
# This script will probably not fully work on stock as each device controls
# LED differently - would require to reverse engineer Merlin's compiled binaries!
#

#shellcheck disable=SC2155

ON_HOUR=6 # hour to turn on the leds
ON_MINUTE=0 # minute to turn on the leds
OFF_HOUR=0 # hour to turn off the leds
OFF_MINUTE=0 # minute to turn off the leds
PERSISTENT=false # should the LED status be persistent between reboots (makes extra writes to the nvram)

# This means that this is a Merlin firmware
if [ -f "/usr/sbin/helper.sh" ]; then
    #shellcheck disable=SC1091
    . /usr/sbin/helper.sh

    ON_HOUR_=$(am_settings_get jl_ledcontrol_on_hour)
    ON_MINUTE_=$(am_settings_get jl_ledcontrol_on_minute)
    OFF_HOUR_=$(am_settings_get jl_ledcontrol_off_hour)
    OFF_MINUTE_=$(am_settings_get jl_ledcontrol_off_minute)

    [ -n "$ON_HOUR_" ] && ON_HOUR=$ON_HOUR_
    [ -n "$ON_MINUTE_" ] && ON_MINUTE=$ON_MINUTE_
    [ -n "$OFF_HOUR_" ] && OFF_HOUR=$OFF_HOUR_
    [ -n "$OFF_MINUTE_" ] && OFF_MINUTE=$OFF_MINUTE_
fi

readonly SCRIPT_NAME="$(basename "$0" .sh)"
readonly SCRIPT_PATH="$(readlink -f "$0")"
readonly SCRIPT_CONFIG="$(dirname "$0")/$SCRIPT_NAME.conf"
if [ -f "$SCRIPT_CONFIG" ]; then
    #shellcheck disable=SC1090
    . "$SCRIPT_CONFIG"
fi

{ [ "$PERSISTENT" = "true" ] || [ "$PERSISTENT" = true ]; } && PERSISTENT="1" || PERSISTENT="0"

PERSISTENT_STATE="$([ "$PERSISTENT" = "1" ] && echo " (preserved)")"

if [ -n "$PERSISTENT_STATE" ] && [ ! -f "/usr/sbin/helper.sh" ]; then
    PERSISTENT_STATE=""
    logger -s -t "$SCRIPT_NAME" "Persistent LED state is only supported on Merlin firmware"
fi

set_wl_leds() {
    _STATE=0
    [ "$1" = "off" ] && _STATE=1

    for _INTERFACE in /sys/class/net/eth*; do
        [ ! -d "$_INTERFACE" ] && continue

        _INTERFACE="$(basename "$_INTERFACE")"
        _STATUS="$(wl -i "$_INTERFACE" status 2>/dev/null)"

        if echo "$_STATUS" | grep -q "2.4GHz" || echo "$_STATUS" | grep -q "5GHz"; then
            wl -i "$_INTERFACE" leddc $_STATE
        fi
    done
}

loop_led_ctrl() {
    _STATE=1
    [ "$1" = "off" ] && _STATE=0

    for _LED in 1 2 3 4 5 6 7 8 9 10 11 12 13 14 15 16 17 18 19 20 21 22 23 24 25; do
        led_ctrl $_LED $_STATE || break
    done
}

switch_leds() {
    case "$1" in
        "on")
            if [ -f "/usr/sbin/helper.sh" ]; then
                [ "$PERSISTENT" = "1" ] && nvram commit
                service restart_leds >/dev/null
            else
                loop_led_ctrl on
                set_wl_leds on
            fi

            logger -s -t "$SCRIPT_NAME" "LEDs are now ON$PERSISTENT_STATE"
        ;;
        "off")
            if [ -f "/usr/sbin/helper.sh" ]; then
                nvram set led_disable=1
                [ "$PERSISTENT" = "1" ] && nvram commit
                service restart_leds >/dev/null
            else
                loop_led_ctrl off
                set_wl_leds off
            fi

            logger -s -t "$SCRIPT_NAME" "LEDs are now OFF$PERSISTENT_STATE"
        ;;
    esac
}

case "$1" in
    "on")
        switch_leds on
    ;;
    "off")
        switch_leds off
    ;;
    "run")
        if [ -n "$ON_HOUR" ] && [ -n "$ON_MINUTE" ] && [ -n "$OFF_HOUR" ] && [ -n "$OFF_MINUTE" ]; then
            _TIMER=0
            _TIMEOUT=60
            while [ "$(nvram get ntp_ready)" = 0 ] && [ "$_TIMER" -lt "$_TIMEOUT" ]; do
                _TIMER=$((_TIMER+1))
                sleep 1
            done

            if [ "$(nvram get ntp_ready)" = 1 ]; then
                on="$(date --date="$ON_HOUR:$ON_MINUTE" +%s)"
                off="$(date --date="$OFF_HOUR:$OFF_MINUTE" +%s)"
                now="$(date +%s)"

                if [ "$on" -le "$off" ]; then
                    [ "$on" -le "$now" ] && [ "$now" -lt "$off" ] && setLedsOn=1 || setLedsOn=0
                else
                    [ "$on" -gt "$now" ] && [ "$now" -ge "$off" ] && setLedsOn=0 || setLedsOn=1
                fi

                if [ "$setLedsOn" = 1 ]; then
                    if [ -f "/usr/sbin/helper.sh" ]; then
                        [ "$(nvram get led_disable)" = 1 ] && sh "$SCRIPT_PATH" off
                    else
                        sh "$SCRIPT_PATH" off
                    fi
                elif [ "$setLedsOn" = 0 ]; then
                    if [ -f "/usr/sbin/helper.sh" ]; then
                        [ "$(nvram get led_disable)" = 0 ] && sh "$SCRIPT_PATH" on
                    else
                        sh "$SCRIPT_PATH" on
                    fi
                fi
            else
                logger -s -t "$SCRIPT_NAME" "NTP not synchronized after 60 seconds, LEDs will switch state with cron"
            fi
        fi
    ;;
    "start")
        if [ -n "$ON_HOUR" ] && [ -n "$ON_MINUTE" ] && [ -n "$OFF_HOUR" ] && [ -n "$OFF_MINUTE" ]; then
            cru a "${SCRIPT_NAME}-On" "$ON_MINUTE $ON_HOUR * * * $SCRIPT_PATH on"
            cru a "${SCRIPT_NAME}-Off" "$OFF_MINUTE $OFF_HOUR * * * $SCRIPT_PATH off"

            logger -s -t "$SCRIPT_NAME" "LED control schedule has been enabled"

            sh "$SCRIPT_PATH" run &
        else
            logger -s -t "$SCRIPT_NAME" "LED control schedule is not set"
        fi
    ;;
    "stop")
        cru d "${SCRIPT_NAME}-On"
        cru d "${SCRIPT_NAME}-Off"

        if [ -f "/usr/sbin/helper.sh" ] && [ "$(nvram get led_disable)" = 1 ]; then
            PERSISTENT="1"
            switch_leds on
        fi

        logger -s -t "$SCRIPT_NAME" "LED control schedule has been disabled"
    ;;
    "restart")
        sh "$SCRIPT_PATH" stop
        sh "$SCRIPT_PATH" start
    ;;
    *)
        echo "Usage: $0 run|on|off|start|stop|restart"
        exit 1
    ;;
esac
