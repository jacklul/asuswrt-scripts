#!/bin/sh
# Made by Jack'lul <jacklul.github.io>
#
# Automatically turn LEDs on/off on by schedule
#
# WARNING: This is hit-or-miss on stock firmware as every model does things differently,
# consider this script proof-of-concept quality
#
# Based on:
#  https://github.com/RMerl/asuswrt-merlin.ng/wiki/Scheduled-LED-control
#  https://github.com/decoderman/amtm/blob/master/amtm_modules/led_control.mod
#

#jas-update=led-control.sh
#shellcheck disable=SC2155
#shellcheck source=./common.sh
readonly common_script="$(dirname "$0")/common.sh"
if [ -f "$common_script" ]; then . "$common_script"; else { echo "$common_script not found" >&2; exit 1; } fi

ON_HOUR=6 # hour to turn on the leds
ON_MINUTE=0 # minute to turn on the leds
OFF_HOUR=0 # hour to turn off the leds
OFF_MINUTE=0 # minute to turn off the leds
PERSISTENT=false # should the LED status be persistent between reboots (makes extra writes to the nvram)

load_script_config

is_merlin_firmware && merlin=true
[ "$PERSISTENT" = true ] && persistent_state=" (preserved)"

if [ -n "$persistent_state" ] && [ -n "$merlin" ]; then
    persistent_state=""
    logecho "Persistent LED state is only supported on Asuswrt-Merlin firmware" stderr
fi

set_wl_leds() {
    _state=0
    [ "$1" = "off" ] && _state=1

    for _interface in /sys/class/net/eth*; do
        [ ! -d "$_interface" ] && continue

        _interface="$(basename "$_interface")"
        _status="$(wl -i "$_interface" status 2> /dev/null)"

        if echo "$_status" | grep -Fq "2.4GHz" || echo "$_status" | grep -Fq "5GHz"; then
            wl -i "$_interface" leddc $_state
        fi
    done
}

loop_led_ctrl() {
    _state=1
    [ "$1" = "off" ] && _state=0

    for _led in 1 2 3 4 5 6 7 8 9 10 11 12 13 14 15 16 17 18 19 20 21 22 23 24 25; do
        led_ctrl $_led $_state || break
    done
}

switch_leds() {
    case "$1" in
        "on")
            if [ -n "$merlin" ]; then
                [ "$PERSISTENT" = true ] && nvram commit
                service restart_leds > /dev/null
            else
                #loop_led_ctrl on
                #set_wl_leds on
                nvram set led_val=1
                service ctrl_led
            fi

            logecho "LEDs are now ON$persistent_state" logger
        ;;
        "off")
            if [ -n "$merlin" ]; then
                nvram set led_disable=1
                [ "$PERSISTENT" = true ] && nvram commit
                service restart_leds > /dev/null
            else
                #loop_led_ctrl off
                #set_wl_leds off
                nvram set led_val=0
                service ctrl_led
            fi

            logecho "LEDs are now OFF$persistent_state" logger
        ;;
    esac
}

run_schedule() {
    if [ -n "$ON_HOUR" ] && [ -n "$ON_MINUTE" ] && [ -n "$OFF_HOUR" ] && [ -n "$OFF_MINUTE" ]; then
        timeout=60
        while [ "$(nvram get ntp_ready)" != "1" ] && [ "$timeout" -ge 0 ]; do
            timeout=$((timeout-1))
            sleep 1
        done

        if [ "$(nvram get ntp_ready)" = "1" ]; then
            on="$(date --date="$ON_HOUR:$ON_MINUTE" +%s)"
            off="$(date --date="$OFF_HOUR:$OFF_MINUTE" +%s)"
            now="$(date +%s)"

            if [ "$on" -le "$off" ]; then
                [ "$on" -le "$now" ] && [ "$now" -lt "$off" ] && set_leds_on=1 || set_leds_on=0
            else
                [ "$on" -gt "$now" ] && [ "$now" -ge "$off" ] && set_leds_on=0 || set_leds_on=1
            fi

            if [ "$set_leds_on" = 1 ]; then
                if [ -n "$merlin" ]; then
                    [ "$(nvram get led_disable)" = 1 ] && sh "$script_path" off
                else
                    sh "$script_path" off
                fi
            elif [ "$set_leds_on" = 0 ]; then
                if [ -n "$merlin" ]; then
                    [ "$(nvram get led_disable)" = 0 ] && sh "$script_path" on
                else
                    sh "$script_path" on
                fi
            fi
        else
            logecho "Time is not synchronized after 60 seconds, LEDs will switch state with cron"
        fi
    fi
}

case "$1" in
    "on")
        switch_leds on
    ;;
    "off")
        switch_leds off
    ;;
    "run")
        run_schedule
    ;;
    "start")
        if [ -n "$ON_HOUR" ] && [ -n "$ON_MINUTE" ] && [ -n "$OFF_HOUR" ] && [ -n "$OFF_MINUTE" ]; then
            crontab_entry add "${script_name}-On" "$ON_MINUTE $ON_HOUR * * * $script_path on"
            crontab_entry add "${script_name}-Off" "$OFF_MINUTE $OFF_HOUR * * * $script_path off"

            logecho "LED control schedule has been enabled" logger

            run_schedule
        else
            logecho "LED control schedule is not set" stderr
        fi
    ;;
    "stop")
        crontab_entry delete "${script_name}-On"
        crontab_entry delete "${script_name}-Off"

        if [ -n "$merlin" ] && [ "$(nvram get led_disable)" = "1" ]; then
            PERSISTENT=true
            switch_leds on
        fi

        logecho "LED control schedule has been disabled" logger
    ;;
    "restart")
        sh "$script_path" stop
        sh "$script_path" start
    ;;
    *)
        echo "Usage: $0 run|start|stop|restart|on|off"
        exit 1
    ;;
esac
