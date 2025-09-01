#!/bin/sh
# Made by Jack'lul <jacklul.github.io>
#
# Automatically turns LEDs on/off on by schedule
#
# WARNING: This is hit-or-miss on stock firmware as every model does things differently,
# consider this script proof-of-concept quality
#
# Based on:
#  https://github.com/RMerl/asuswrt-merlin.ng/wiki/Scheduled-LED-control
#  https://github.com/decoderman/amtm/blob/master/amtm_modules/led_control.mod
#

#jacklul-asuswrt-scripts-update=led-control.sh
#shellcheck disable=SC2155

readonly script_path="$(readlink -f "$0")"
readonly script_name="$(basename "$script_path" .sh)"
readonly script_dir="$(dirname "$script_path")"
readonly script_config="$script_dir/$script_name.conf"

ON_HOUR=6 # hour to turn on the leds
ON_MINUTE=0 # minute to turn on the leds
OFF_HOUR=0 # hour to turn off the leds
OFF_MINUTE=0 # minute to turn off the leds
PERSISTENT=false # should the LED status be persistent between reboots (makes extra writes to the nvram)

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
persistent_state="$([ "$PERSISTENT" = true ] && echo " (preserved)")"

if [ -n "$persistent_state" ] && [ -n "$merlin" ]; then
    persistent_state=""
    logger -st "$script_name" "Persistent LED state is only supported on Asuswrt-Merlin firmware"
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

            logger -st "$script_name" "LEDs are now ON$persistent_state"
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

            logger -st "$script_name" "LEDs are now OFF$persistent_state"
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
                logger -st "$script_name" "Time is not synchronized after 60 seconds, LEDs will switch state with cron"
            fi
        fi
    ;;
    "start")
        if [ -n "$ON_HOUR" ] && [ -n "$ON_MINUTE" ] && [ -n "$OFF_HOUR" ] && [ -n "$OFF_MINUTE" ]; then
            cru a "${script_name}-On" "$ON_MINUTE $ON_HOUR * * * $script_path on"
            cru a "${script_name}-Off" "$OFF_MINUTE $OFF_HOUR * * * $script_path off"

            logger -st "$script_name" "LED control schedule has been enabled"

            sh "$script_path" run &
        else
            logger -st "$script_name" "LED control schedule is not set"
        fi
    ;;
    "stop")
        cru d "${script_name}-On"
        cru d "${script_name}-Off"

        if [ -n "$merlin" ] && [ "$(nvram get led_disable)" = 1 ]; then
            PERSISTENT=true
            switch_leds on
        fi

        logger -st "$script_name" "LED control schedule has been disabled"
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
