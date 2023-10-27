#!/bin/sh
# Made by Jack'lul <jacklul.github.io>
#
# Apply tweaks to the WebUI dynamically
#

#shellcheck disable=SC2155

readonly SCRIPT_PATH="$(readlink -f "$0")"
readonly SCRIPT_NAME="$(basename "$SCRIPT_PATH" .sh)"
readonly SCRIPT_DIR="$(dirname "$SCRIPT_PATH")"
readonly SCRIPT_CONFIG="$SCRIPT_DIR/$SCRIPT_NAME.conf"
#readonly SCRIPT_TAG="$(basename "$SCRIPT_PATH")"

if [ -f "$SCRIPT_CONFIG" ]; then
    #shellcheck disable=SC1090
    . "$SCRIPT_CONFIG"
fi

TMP_WWW_PATH="/tmp/$SCRIPT_NAME/www"

cpu_temperature_on_status() {
    case "$1" in
        "set")
            if ! mount | grep -q "$TMP_WWW_PATH/cpu_ram_status.asp"; then
                cp -f /www/cpu_ram_status.asp "$TMP_WWW_PATH/cpu_ram_status.asp"

                echo "cpuTemp = '<%get_cpu_temperature();%>';" >> "$TMP_WWW_PATH/cpu_ram_status.asp"

                mount --bind "$TMP_WWW_PATH/cpu_ram_status.asp" /www/cpu_ram_status.asp
            fi

            if ! mount | grep -q "$TMP_WWW_PATH/device-map/router_status.asp"; then
                mkdir -p "$TMP_WWW_PATH/device-map"
                cp -f /www/device-map/router_status.asp "$TMP_WWW_PATH/device-map/router_status.asp"

                sed -i 's@render_CPU(cpuInfo);@render_CPU(cpuInfo, cpuTemp);@g' "$TMP_WWW_PATH/device-map/router_status.asp"
                sed -i 's@function(cpu_info_new)@function(cpu_info_new, cpu_temp_new)@g' "$TMP_WWW_PATH/device-map/router_status.asp"
                sed -i "s@Object.keys(cpu_info_new).length;@Object.keys(cpu_info_new).length;\$(\"#cpu_temp\").html(cpu_temp_new);@g" "$TMP_WWW_PATH/device-map/router_status.asp"
                sed -i "s@\$('#cpu_field').html(code);@code += '<div class=\"info-block\">Temperature: <span id=\"cpu_temp\"></span>°C</div>';\$('#cpu_field').html(code);@g" "$TMP_WWW_PATH/device-map/router_status.asp"

                mount --bind "$TMP_WWW_PATH/device-map/router_status.asp" /www/device-map/router_status.asp
            fi
        ;;
        "unset")
            if mount | grep -q "/www/cpu_ram_status.asp"; then
                umount "/www/cpu_ram_status.asp"
                rm -f "$TMP_WWW_PATH/cpu_ram_status.asp"
            fi

            if mount | grep -q "/www/device-map/router_status.asp"; then
                umount "/www/device-map/router_status.asp"
                rm -f "$TMP_WWW_PATH/device-map/router_status.asp"
            fi
        ;;
    esac
}

www_override() {
    case "$1" in
        "set")
            mkdir -p "$TMP_WWW_PATH"

            cpu_temperature_on_status set
        ;;
        "unset")
            cpu_temperature_on_status unset

            rm -fr "$TMP_WWW_PATH"
        ;;
    esac
}

case "$1" in
    "start")
        www_override set
    ;;
    "stop")
        www_override unset
    ;;
    "restart")
        sh "$SCRIPT_PATH" stop
        sh "$SCRIPT_PATH" start
    ;;
    *)
        echo "Usage: $0 start|stop|restart"
        exit 1
    ;;
esac
