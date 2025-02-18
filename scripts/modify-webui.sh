#!/bin/sh
# Made by Jack'lul <jacklul.github.io>
#
# Apply tweaks to the WebUI dynamically
#

#jacklul-asuswrt-scripts-update
#shellcheck disable=SC2155,SC2016

readonly SCRIPT_PATH="$(readlink -f "$0")"
readonly SCRIPT_NAME="$(basename "$SCRIPT_PATH" .sh)"
readonly SCRIPT_DIR="$(dirname "$SCRIPT_PATH")"
readonly SCRIPT_CONFIG="$SCRIPT_DIR/$SCRIPT_NAME.conf"
readonly SCRIPT_TAG="$(basename "$SCRIPT_PATH")"

TWEAKS="cpu_temperature guest_wifi_qr_code notrendmicro_support https_lanport_allow_443" # list of tweaks to apply
TMP_WWW_PATH="/tmp/$SCRIPT_NAME/www"

if [ -f "$SCRIPT_CONFIG" ]; then
    #shellcheck disable=SC1090
    . "$SCRIPT_CONFIG"
fi

[ -f "/usr/sbin/helper.sh" ] && MERLIN="1"

# these two sed_* functions are taken/based on https://github.com/RMerl/asuswrt-merlin.ng/blob/master/release/src/router/others/helper.sh
sed_quote() {
    printf "%s\n" "$1" | sed 's/[]\/$*.^&[]/\\&/g'
}

sed_and_check() {
    _MD5SUM="$(md5sum "$4" | awk '{print $1}')"

    PATTERN=$(sed_quote "$2")
    CONTENT=$(sed_quote "$3")

    case "$1" in
        "replace")
            sed -i "s/$PATTERN/$CONTENT/" "$4"
        ;;
        "before")
            sed -i "/$PATTERN/i$CONTENT" "$4"
        ;;
        "after")
            sed -i "/$PATTERN/a$CONTENT" "$4"
        ;;
        *)
            echo "Invalid mode: $1"
            return
        ;;
    esac

    _MD5SUM2="$(md5sum "$4" | awk '{print $1}')"

    if [ "$_MD5SUM" != "$_MD5SUM2" ]; then
        return 0
    fi

    logger -st "$SCRIPT_TAG" "Failed to apply modification to $(basename "$4"): sed $1  \"$2\"  \"$3\""

    return 1
}

cpu_temperature() {
    case "$1" in
        "set")
            if ! mount | grep -q /www/cpu_ram_status.asp; then
                [ ! -f "$TMP_WWW_PATH/cpu_ram_status.asp" ] && cp -f /www/cpu_ram_status.asp "$TMP_WWW_PATH/cpu_ram_status.asp"

                echo "cpuTemp = '<%get_cpu_temperature();%>';" >> "$TMP_WWW_PATH/cpu_ram_status.asp"

                mount --bind "$TMP_WWW_PATH/cpu_ram_status.asp" /www/cpu_ram_status.asp
            fi

            if ! mount | grep -q /www/device-map/router_status.asp; then
                mkdir -p "$TMP_WWW_PATH/device-map"
                [ ! -f "$TMP_WWW_PATH/device-map/router_status.asp" ] && cp -f /www/device-map/router_status.asp "$TMP_WWW_PATH/device-map/router_status.asp"

                sed_and_check replace 'render_CPU(cpuInfo);' 'render_CPU(cpuInfo, cpuTemp);' "$TMP_WWW_PATH/device-map/router_status.asp"
                sed_and_check replace 'function(cpu_info_new)' 'function(cpu_info_new, cpu_temp_new)' "$TMP_WWW_PATH/device-map/router_status.asp"
                sed_and_check after 'Object.keys(cpu_info_new).length;' '$("#cpu_temp").html(parseFloat(cpu_temp_new).toFixed(1));' "$TMP_WWW_PATH/device-map/router_status.asp"
                sed_and_check before "('#cpu_field').html(code);" "code += '<div class=\"info-block\">Temperature: <span id=\"cpu_temp\"></span> °C</div>';" "$TMP_WWW_PATH/device-map/router_status.asp"

                mount --bind "$TMP_WWW_PATH/device-map/router_status.asp" /www/device-map/router_status.asp
            fi
        ;;
        "unset")
            if mount | grep -q /www/cpu_ram_status.asp; then
                umount /www/cpu_ram_status.asp
                rm -f "$TMP_WWW_PATH/cpu_ram_status.asp"
            fi

            if mount | grep -q /www/device-map/router_status.asp; then
                umount /www/device-map/router_status.asp
                rm -f "$TMP_WWW_PATH/device-map/router_status.asp"
            fi
        ;;
    esac
}

guest_wifi_qr_code() {
    case "$1" in
        "set")
            if ! mount | grep -q /www/Guest_network.asp; then
                [ ! -f "$TMP_WWW_PATH/Guest_network.asp" ] && cp -f /www/Guest_network.asp "$TMP_WWW_PATH/Guest_network.asp"

                sed_and_check after '<script type="text/javascript" src="js/httpApi.js"></script>' '<script src="https://cdn.rawgit.com/davidshimjs/qrcodejs/gh-pages/qrcode.min.js"></script>' "$TMP_WWW_PATH/Guest_network.asp"
                sed_and_check after 'onclick="applyRule();">' '<br><span id="qr_code" style="display:inline-block;margin:25px 0 25px 0;"></span>' "$TMP_WWW_PATH/Guest_network.asp"
                sed_and_check replace 'gn_array[i][4];' "'Hidden'" "$TMP_WWW_PATH/Guest_network.asp"
                sed_and_check replace 'gn_array[i][key_index];' "'Hidden'" "$TMP_WWW_PATH/Guest_network.asp"
                sed_and_check after 'updateMacModeOption()' 'var qrstring="WIFI:S:"+document.form.wl_ssid.value+";";document.form.wl_wpa_psk.value&&0<document.form.wl_wpa_psk.value.length?qrstring+="T:WPA;P:"+document.form.wl_wpa_psk.value+";":qrstring+="T:nopass;",1==document.form.wl_closed[0].checked&&(qrstring+="H:true;"),document.getElementById("qr_code").innerHTML="",new QRCode(document.getElementById("qr_code"),{text:qrstring+";",width:500,height:500});' "$TMP_WWW_PATH/Guest_network.asp"

                mount --bind "$TMP_WWW_PATH/Guest_network.asp" /www/Guest_network.asp
            fi
        ;;
        "unset")
            if mount | grep -q /www/Guest_network.asp; then
                umount /www/Guest_network.asp
                rm -f "$TMP_WWW_PATH/Guest_network.asp"
            fi
        ;;
    esac
}

notrendmicro_support() {
    case "$1" in
        "set")
            if ! mount | grep -q /www/state.js; then
                [ ! -f "$TMP_WWW_PATH/state.js" ] && cp -f /www/state.js "$TMP_WWW_PATH/state.js"

                sed_and_check after 'var lyra_hide_support = isSupport("lyra_hide")' 'var notrendmicro_support = isSupport("notrendmicro");' "$TMP_WWW_PATH/state.js"

                mount --bind "$TMP_WWW_PATH/state.js" /www/state.js
            fi

            if ! mount | grep -q /www/require/modules/menuTree.js; then
                mkdir -p "$TMP_WWW_PATH/require/modules"
                [ ! -f "$TMP_WWW_PATH/require/modules/menuTree.js" ] && cp -f /www/require/modules/menuTree.js "$TMP_WWW_PATH/require/modules/menuTree.js"

                INTERNETSPEED_TAB="$(grep 'url: "AdaptiveQoS_InternetSpeed\.asp' /www/require/modules/menuTree.js | tail -n 1)"

                if [ -n "$INTERNETSPEED_TAB" ]; then
                    sed_and_check replace '{url: "AdaptiveQoS_InternetSpeed.asp"' '//{url: "AdaptiveQoS_InternetSpeed.asp"' "$TMP_WWW_PATH/require/modules/menuTree.js"
                    sed_and_check after '{url: "Advanced_Smart_Connect.asp' "$INTERNETSPEED_TAB" "$TMP_WWW_PATH/require/modules/menuTree.js"
                else
                    logger -st "$SCRIPT_TAG" "There was a problem running modification on file $TMP_WWW_PATH/require/modules/menuTree.js: unable to find AdaptiveQoS_InternetSpeed line"
                fi

                sed_and_check before 'return menuTree;' 'menuTree.exclude.menus=function(){var t=menuTree.exclude.menus;return function(){var e=t.apply(this,arguments);return!ParentalCtrl2_support&&notrendmicro_support&&e.push("menu_ParentalControl"),notrendmicro_support&&(e.push("menu_AiProtection"),e.push("menu_BandwidthMonitor")),e}}(),menuTree.exclude.tabs=function(){var t=menuTree.exclude.tabs;return function(){var e=t.apply(this,arguments);return notrendmicro_support&&(e.push("AiProtection_HomeProtection.asp"),e.push("AiProtection_MaliciousSitesBlocking.asp"),e.push("AiProtection_IntrusionPreventionSystem.asp"),e.push("AiProtection_InfectedDevicePreventBlock.asp"),e.push("AiProtection_AdBlock.asp"),e.push("AiProtection_Key_Guard.asp"),e.push("AdaptiveQoS_ROG.asp"),e.push("AiProtection_WebProtector.asp"),e.push("AdaptiveQoS_Bandwidth_Monitor.asp"),e.push("QoS_EZQoS.asp"),e.push("AdaptiveQoS_WebHistory.asp"),e.push("AdaptiveQoS_ROG.asp"),e.push("Advanced_QOSUserPrio_Content.asp"),e.push("Advanced_QOSUserRules_Content.asp"),e.push("AdaptiveQoS_Adaptive.asp"),e.push("TrafficAnalyzer_Statistic.asp"),e.push("AdaptiveQoS_TrafficLimiter.asp")),e}}();' "$TMP_WWW_PATH/require/modules/menuTree.js"

                if [ -n "$MERLIN" ]; then
                    cp -f "$TMP_WWW_PATH/require/modules/menuTree.js" /tmp/menuTree.js
                    mount --bind /tmp/menuTree.js /www/require/modules/menuTree.js
                else
                    mount --bind "$TMP_WWW_PATH/require/modules/menuTree.js" /www/require/modules/menuTree.js
                fi
            fi
        ;;
        "unset")
            [ -n "$MERLIN" ] && { logger -st "$SCRIPT_TAG" "Unable to revert 'notrendmicro_support' tweak on Asuswrt-Merlin firmware - restart required!"; return; }

            if mount | grep -q /www/state.js; then
                umount /www/state.js
                rm -f "$TMP_WWW_PATH/state.js"
            fi

            if mount | grep -q /www/require/modules/menuTree.js; then
                umount /www/require/modules/menuTree.js
                rm -f "$TMP_WWW_PATH/require/modules/menuTree.js"
            fi
        ;;
    esac
}

https_lanport_allow_443() {
    case "$1" in
        "set")
            if ! mount | grep -q /www/Advanced_System_Content.asp; then
                [ ! -f "$TMP_WWW_PATH/Advanced_System_Content.asp" ] && cp -f /www/Advanced_System_Content.asp "$TMP_WWW_PATH/Advanced_System_Content.asp"

                sed_and_check replace '&& !validator.range(document.form.https_lanport, 1024, 65535) &&' "&& (document.form.https_lanport.value != 443 && !validator.range(document.form.https_lanport, 1024, 65535)) &&" "$TMP_WWW_PATH/Advanced_System_Content.asp"

                mount --bind "$TMP_WWW_PATH/Advanced_System_Content.asp" /www/Advanced_System_Content.asp
            fi
        ;;
        "unset")
            if mount | grep -q /www/Advanced_System_Content.asp; then
                umount /www/Advanced_System_Content.asp
                rm -f "$TMP_WWW_PATH/Advanced_System_Content.asp"
            fi
        ;;
    esac
}

www_override() {
    case "$1" in
        "set")
            mkdir -p "$TMP_WWW_PATH"

            logger -st "$SCRIPT_TAG" "Applying WebUI tweaks: $TWEAKS"

            for TWEAK in $TWEAKS; do
                $TWEAK set
            done
        ;;
        "unset")
            logger -st "$SCRIPT_TAG" "Removing WebUI tweaks..."

            cpu_temperature unset
            guest_wifi_qr_code unset
            notrendmicro_support unset
            https_lanport_allow_443 unset

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
