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
#shellcheck shell=ash
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
    logecho "Persistent LED state is only supported on Asuswrt-Merlin firmware" error
fi

set_wl_leds() {
    local _state=0
    [ "$1" = "off" ] && _state=1

    local _interface _status

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
    local _state=1
    [ "$1" = "off" ] && _state=0

    local _led
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

            logecho "LEDs are now ON$persistent_state" alert
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

            logecho "LEDs are now OFF$persistent_state" alert
        ;;
    esac
}

run_schedule() {
    if [ -n "$ON_HOUR" ] && [ -n "$ON_MINUTE" ] && [ -n "$OFF_HOUR" ] && [ -n "$OFF_MINUTE" ]; then
        local _timeout=60
        while [ "$(nvram get ntp_ready)" != "1" ] && [ "$_timeout" -ge 0 ]; do
            _timeout=$((_timeout-1))
            sleep 1
        done

        if [ "$(nvram get ntp_ready)" = "1" ]; then
            local _on="$(date --date="$ON_HOUR:$ON_MINUTE" +%s)"
            local _off="$(date --date="$OFF_HOUR:$OFF_MINUTE" +%s)"
            local _now="$(date +%s)"
            local _set_leds_on _set_leds_off

            if [ "$_on" -le "$_off" ]; then
                [ "$_on" -le "$_now" ] && [ "$_now" -lt "$_off" ] && _set_leds_on=1 || _set_leds_on=0
            else
                [ "$_on" -gt "$_now" ] && [ "$_now" -ge "$_off" ] && _set_leds_on=0 || _set_leds_on=1
            fi

            if [ "$_set_leds_on" = 1 ]; then
                if [ -n "$merlin" ]; then
                    [ "$(nvram get led_disable)" = 1 ] && sh "$script_path" off
                else
                    sh "$script_path" off
                fi
            elif [ "$_set_leds_on" = 0 ]; then
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

            logecho "LED control schedule has been enabled" alert

            run_schedule
        else
            logecho "LED control schedule is not set" error
        fi
    ;;
    "stop")
        crontab_entry delete "${script_name}-On"
        crontab_entry delete "${script_name}-Off"

        if [ -n "$merlin" ] && [ "$(nvram get led_disable)" = "1" ]; then
            PERSISTENT=true
            switch_leds on
        fi

        logecho "LED control schedule has been disabled" alert
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
