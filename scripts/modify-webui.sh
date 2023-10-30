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
readonly SCRIPT_TAG="$(basename "$SCRIPT_PATH")"

TWEAKS="cpu_temperature guest_wifi_qr_code notrendmicro_support" # list of tweaks to apply

if [ -f "$SCRIPT_CONFIG" ]; then
    #shellcheck disable=SC1090
    . "$SCRIPT_CONFIG"
fi

TMP_WWW_PATH="/tmp/$SCRIPT_NAME/www"

replace_and_check() {
    _SED="$1"
    _FILE="$2"

    _MD5SUM="$(md5sum "$_FILE" | awk '{print $1}')"

    sed -i "$_SED" "$_FILE"

    _MD5SUM2="$(md5sum "$_FILE" | awk '{print $1}')"

    if [ "$_MD5SUM" != "$_MD5SUM2" ]; then
        return 0
    fi

    logger -st "$SCRIPT_TAG" "There was a problem running modification on file $_FILE: $_SED"

    return 1
}

cpu_temperature() {
    case "$1" in
        "set")
            if ! mount | grep -q "/www/cpu_ram_status.asp"; then
                [ ! -f "$TMP_WWW_PATH/cpu_ram_status.asp" ] && cp -f /www/cpu_ram_status.asp "$TMP_WWW_PATH/cpu_ram_status.asp"

                echo "cpuTemp = '<%get_cpu_temperature();%>';" >> "$TMP_WWW_PATH/cpu_ram_status.asp"

                mount --bind "$TMP_WWW_PATH/cpu_ram_status.asp" /www/cpu_ram_status.asp
            fi

            if ! mount | grep -q "/www/device-map/router_status.asp"; then
                mkdir -p "$TMP_WWW_PATH/device-map"
                [ ! -f "$TMP_WWW_PATH/device-map/router_status.asp" ] && cp -f /www/device-map/router_status.asp "$TMP_WWW_PATH/device-map/router_status.asp"

                replace_and_check 's@render_CPU(cpuInfo);@render_CPU(cpuInfo, cpuTemp);@g' "$TMP_WWW_PATH/device-map/router_status.asp"
                replace_and_check 's@function(cpu_info_new)@function(cpu_info_new, cpu_temp_new)@g' "$TMP_WWW_PATH/device-map/router_status.asp"
                replace_and_check "s@Object.keys(cpu_info_new).length;@Object.keys(cpu_info_new).length;\n\$(\"#cpu_temp\").html(parseFloat(cpu_temp_new).toFixed(1));@g" "$TMP_WWW_PATH/device-map/router_status.asp"
                replace_and_check "s@\$('#cpu_field').html(code);@code += '<div class=\"info-block\">Temperature: <span id=\"cpu_temp\"></span> °C</div>';\n\$('#cpu_field').html(code);@g" "$TMP_WWW_PATH/device-map/router_status.asp"

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

guest_wifi_qr_code() {
    case "$1" in
        "set")
            if ! mount | grep -q "/www/Guest_network.asp"; then
                [ ! -f "$TMP_WWW_PATH/Guest_network.asp" ] && cp -f /www/Guest_network.asp "$TMP_WWW_PATH/Guest_network.asp"

                replace_and_check 's@<script type="text/javascript" src="js/httpApi.js"></script>@<script type="text/javascript" src="js/httpApi.js"></script>\n<script src="https://cdn.rawgit.com/davidshimjs/qrcodejs/gh-pages/qrcode.min.js"></script>@g' "$TMP_WWW_PATH/Guest_network.asp"
                replace_and_check 's@onclick="applyRule();">@onclick="applyRule();">\n<br><span id="qr_code" style="display:inline-block;margin:25px 0 25px 0;"></span>@g' "$TMP_WWW_PATH/Guest_network.asp"
                replace_and_check "s@gn_array\[i\]\[4\];@'Hidden';@g" "$TMP_WWW_PATH/Guest_network.asp"
                replace_and_check "s@gn_array\[i\]\[key_index\];@'Hidden';@g" "$TMP_WWW_PATH/Guest_network.asp"
                replace_and_check 's@updateMacModeOption();@updateMacModeOption();\nvar qrstring="WIFI:S:"+document.form.wl_ssid.value+";";document.form.wl_wpa_psk.value\&\&0<document.form.wl_wpa_psk.value.length?qrstring+="T:WPA;P:"+document.form.wl_wpa_psk.value+";":qrstring+="T:nopass;",1==document.form.wl_closed[0].checked\&\&(qrstring+="H:true;"),document.getElementById("qr_code").innerHTML="",new QRCode(document.getElementById("qr_code"),{text:qrstring+";",width:500,height:500});@g' "$TMP_WWW_PATH/Guest_network.asp"

                mount --bind "$TMP_WWW_PATH/Guest_network.asp" /www/Guest_network.asp
            fi
        ;;
        "unset")
            if mount | grep -q "/www/Guest_network.asp"; then
                umount "/www/Guest_network.asp"
                rm -f "$TMP_WWW_PATH/Guest_network.asp"
            fi

            rm -fr "$TMP_WWW_PATH"
        ;;
    esac
}

notrendmicro_support() {
    case "$1" in
        "set")
            if ! mount | grep -q "/www/state.js"; then
                [ ! -f "$TMP_WWW_PATH/state.js" ] && cp -f /www/state.js "$TMP_WWW_PATH/state.js"

                replace_and_check 's@var lyra_hide_support = isSupport("lyra_hide");@var lyra_hide_support = isSupport("lyra_hide");\nvar notrendmicro_support = isSupport("notrendmicro");@g' "$TMP_WWW_PATH/state.js"

                mount --bind "$TMP_WWW_PATH/state.js" /www/state.js
            fi

            if ! mount | grep -q "/www/require/modules/menuTree.js"; then
                mkdir -p "$TMP_WWW_PATH/require/modules"
                [ ! -f "$TMP_WWW_PATH/require/modules/menuTree.js" ] && cp -f /www/require/modules/menuTree.js "$TMP_WWW_PATH/require/modules/menuTree.js"

                INTERNETSPEED_TAB="$(grep -P '{url: "AdaptiveQoS_InternetSpeed\.asp.*tabName:.*"(.*)"},' -o "/www/require/modules/menuTree.js" | head -n 1)"

                replace_and_check 's@return menuTree;@menuTree.exclude.menus=function(){var t=menuTree.exclude.menus;return function(){var e=t.apply(this,arguments);return!ParentalCtrl2_support\&\&notrendmicro_support\&\&e.push("menu_ParentalControl"),notrendmicro_support\&\&(e.push("menu_AiProtection"),e.push("menu_BandwidthMonitor")),e}}(),menuTree.exclude.tabs=function(){var t=menuTree.exclude.tabs;return function(){var e=t.apply(this,arguments);return notrendmicro_support\&\&(e.push("AiProtection_HomeProtection.asp"),e.push("AiProtection_MaliciousSitesBlocking.asp"),e.push("AiProtection_IntrusionPreventionSystem.asp"),e.push("AiProtection_InfectedDevicePreventBlock.asp"),e.push("AiProtection_AdBlock.asp"),e.push("AiProtection_Key_Guard.asp"),e.push("AdaptiveQoS_ROG.asp"),e.push("AiProtection_WebProtector.asp"),e.push("AdaptiveQoS_Bandwidth_Monitor.asp"),e.push("QoS_EZQoS.asp"),e.push("AdaptiveQoS_WebHistory.asp"),e.push("AdaptiveQoS_ROG.asp"),e.push("Advanced_QOSUserPrio_Content.asp"),e.push("Advanced_QOSUserRules_Content.asp"),e.push("AdaptiveQoS_Adaptive.asp"),e.push("TrafficAnalyzer_Statistic.asp"),e.push("AdaptiveQoS_TrafficLimiter.asp")),e}}();\nreturn menuTree;@g' "$TMP_WWW_PATH/require/modules/menuTree.js"

                replace_and_check 's@{url: "AdaptiveQoS_InternetSpeed.asp"@//{url: "AdaptiveQoS_InternetSpeed.asp"@g' "$TMP_WWW_PATH/require/modules/menuTree.js"
                replace_and_check 's@{url: "Advanced_Smart_Connect.asp"@'"$INTERNETSPEED_TAB"'\n{url: "Advanced_Smart_Connect.asp"@g' "$TMP_WWW_PATH/require/modules/menuTree.js"

                mount --bind "$TMP_WWW_PATH/require/modules/menuTree.js" /www/require/modules/menuTree.js
            fi
        ;;
        "unset")
            if mount | grep -q "/www/state.js"; then
                umount "/www/state.js"
                rm -f "$TMP_WWW_PATH/state.js"
            fi

            if mount | grep -q "/www/require/modules/menuTree.js"; then
                umount "/www/require/modules/menuTree.js"
                rm -f "$TMP_WWW_PATH/require/modules/menuTree.js"
            fi

            rm -fr "$TMP_WWW_PATH"
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
