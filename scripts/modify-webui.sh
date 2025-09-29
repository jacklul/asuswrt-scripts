#!/bin/sh
# Made by Jack'lul <jacklul.github.io>
#
# Apply custom tweaks to the WebUI
#

#jas-update=modify-webui.sh
#shellcheck disable=SC2155
#shellcheck source=./common.sh
readonly common_script="$(dirname "$0")/common.sh"
if [ -f "$common_script" ]; then . "$common_script"; else { echo "$common_script not found" >&2; exit 1; } fi

TWEAKS="cpu_temperature guest_wifi_qr_code notrendmicro_support https_lanport_allow_443" # list of tweaks to apply
TMP_WWW_DIR="$TMP_DIR/$script_name-www" # directory to store modified files in

load_script_config

is_merlin_firmware && merlin=true

sed_and_check() {
    _md5sum="$(md5sum "$4" | awk '{print $1}')"

    sed_helper "$1" "$2" "$3" "$4"

    if [ "$_md5sum" != "$(md5sum "$4" | awk '{print $1}')" ]; then
        return 0
    fi

    logecho "Failed to apply modification to '$(basename "$4")':  '$1'  '$2'  '$3'" error

    return 1
}

#shellcheck disable=SC2016
cpu_temperature() {
    _applied=
    case "$1" in
        "set")
            if ! mount | grep -Fq /www/cpu_ram_status.asp; then
                [ ! -f "$TMP_WWW_DIR/cpu_ram_status.asp" ] && cp -f /www/cpu_ram_status.asp "$TMP_WWW_DIR/cpu_ram_status.asp"

                echo "cpuTemp = '<%get_cpu_temperature();%>';" >> "$TMP_WWW_DIR/cpu_ram_status.asp"
                _applied=1

                mount --bind "$TMP_WWW_DIR/cpu_ram_status.asp" /www/cpu_ram_status.asp
            fi

            if ! mount | grep -Fq /www/device-map/router_status.asp; then
                mkdir -p "$TMP_WWW_DIR/device-map"
                [ ! -f "$TMP_WWW_DIR/device-map/router_status.asp" ] && cp -f /www/device-map/router_status.asp "$TMP_WWW_DIR/device-map/router_status.asp"

                sed_and_check replace 'render_CPU(cpuInfo);' 'render_CPU(cpuInfo, cpuTemp);' "$TMP_WWW_DIR/device-map/router_status.asp" && \
                sed_and_check replace 'function(cpu_info_new)' 'function(cpu_info_new, cpu_temp_new)' "$TMP_WWW_DIR/device-map/router_status.asp" && \
                sed_and_check append 'Object.keys(cpu_info_new).length;' '$("#cpu_temp").html(parseFloat(cpu_temp_new).toFixed(1));' "$TMP_WWW_DIR/device-map/router_status.asp" && \
                sed_and_check prepend "('#cpu_field').html(code);" "code += '<div class=\"info-block\">Temperature: <span id=\"cpu_temp\"></span> °C</div>';" "$TMP_WWW_DIR/device-map/router_status.asp" && \
                    _applied=1

                mount --bind "$TMP_WWW_DIR/device-map/router_status.asp" /www/device-map/router_status.asp
            fi
        ;;
        "unset")
            if mount | grep -Fq /www/cpu_ram_status.asp; then
                umount /www/cpu_ram_status.asp
                rm -f "$TMP_WWW_DIR/cpu_ram_status.asp"
            fi

            if mount | grep -Fq /www/device-map/router_status.asp; then
                umount /www/device-map/router_status.asp
                rm -f "$TMP_WWW_DIR/device-map/router_status.asp"
            fi
        ;;
    esac
    [ -z "$_applied" ] && return 1
}

guest_wifi_qr_code() {
    _applied=
    case "$1" in
        "set")
            if ! mount | grep -Fq /www/Guest_network.asp; then
                [ ! -f "$TMP_WWW_DIR/Guest_network.asp" ] && cp -f /www/Guest_network.asp "$TMP_WWW_DIR/Guest_network.asp"

                sed_and_check append '<script type="text/javascript" src="js/httpApi.js"></script>' '<script src="https://cdn.rawgit.com/davidshimjs/qrcodejs/gh-pages/qrcode.min.js"></script>' "$TMP_WWW_DIR/Guest_network.asp" && \
                sed_and_check append 'onclick="applyRule();">' '<br><span id="qr_code" style="display:inline-block;margin:25px 0 25px 0;"></span>' "$TMP_WWW_DIR/Guest_network.asp" && \
                sed_and_check replace 'gn_array[i][4];' "'Hidden'" "$TMP_WWW_DIR/Guest_network.asp" && \
                sed_and_check replace 'gn_array[i][key_index];' "'Hidden'" "$TMP_WWW_DIR/Guest_network.asp" && \
                sed_and_check append 'updateMacModeOption()' 'var qrstring="WIFI:S:"+document.form.wl_ssid.value+";";document.form.wl_wpa_psk.value&&0<document.form.wl_wpa_psk.value.length?qrstring+="T:WPA;P:"+document.form.wl_wpa_psk.value+";":qrstring+="T:nopass;",1==document.form.wl_closed[0].checked&&(qrstring+="H:true;"),document.getElementById("qr_code").innerHTML="",new QRCode(document.getElementById("qr_code"),{text:qrstring+";",width:500,height:500});' "$TMP_WWW_DIR/Guest_network.asp" && \
                    _applied=1

                mount --bind "$TMP_WWW_DIR/Guest_network.asp" /www/Guest_network.asp
            fi
        ;;
        "unset")
            if mount | grep -Fq /www/Guest_network.asp; then
                umount /www/Guest_network.asp
                rm -f "$TMP_WWW_DIR/Guest_network.asp"
            fi
        ;;
    esac
    [ -z "$_applied" ] && return 1
}

notrendmicro_support() {
    _applied=
    case "$1" in
        "set")
            if ! mount | grep -Fq /www/state.js; then
                [ ! -f "$TMP_WWW_DIR/state.js" ] && cp -f /www/state.js "$TMP_WWW_DIR/state.js"

                sed_and_check append 'var lyra_hide_support = isSupport("lyra_hide")' 'var notrendmicro_support = isSupport("notrendmicro");' "$TMP_WWW_DIR/state.js" && \
                    _applied=1

                mount --bind "$TMP_WWW_DIR/state.js" /www/state.js
            fi

            # Doesn't matter if this is Merlin firmware and menuTree.js was already modified, we can still reference it by orignal path since it will be mounted
            if ! mount | grep -Fq /www/require/modules/menuTree.js || ! grep -Fq 'notrendmicro_support' /www/require/modules/menuTree.js; then
                mkdir -p "$TMP_WWW_DIR/require/modules"
                [ ! -f "$TMP_WWW_DIR/require/modules/menuTree.js" ] && cp -f /www/require/modules/menuTree.js "$TMP_WWW_DIR/require/modules/menuTree.js"

                inetspeed_tab="$(grep -F 'url: "AdaptiveQoS_InternetSpeed.asp' /www/require/modules/menuTree.js | tail -n 1)"

                if [ -n "$inetspeed_tab" ]; then
                    sed_and_check replace '{url: "AdaptiveQoS_InternetSpeed.asp"' '//{url: "AdaptiveQoS_InternetSpeed.asp"' "$TMP_WWW_DIR/require/modules/menuTree.js" && \
                    sed_and_check append '{url: "Advanced_Smart_Connect.asp' "$inetspeed_tab" "$TMP_WWW_DIR/require/modules/menuTree.js"
                else
                    logecho "There was a problem performing modification on file '$TMP_WWW_DIR/require/modules/menuTree.js': unable to find line containing 'AdaptiveQoS_InternetSpeed'!" error
                fi

                sed_and_check prepend 'return menuTree;' 'menuTree.exclude.menus=function(){var t=menuTree.exclude.menus;return function(){var e=t.apply(this,arguments);return!ParentalCtrl2_support&&notrendmicro_support&&e.push("menu_ParentalControl"),notrendmicro_support&&(e.push("menu_AiProtection"),e.push("menu_BandwidthMonitor")),e}}(),menuTree.exclude.tabs=function(){var t=menuTree.exclude.tabs;return function(){var e=t.apply(this,arguments);return notrendmicro_support&&(e.push("AiProtection_HomeProtection.asp"),e.push("AiProtection_MaliciousSitesBlocking.asp"),e.push("AiProtection_IntrusionPreventionSystem.asp"),e.push("AiProtection_InfectedDevicePreventBlock.asp"),e.push("AiProtection_AdBlock.asp"),e.push("AiProtection_Key_Guard.asp"),e.push("AdaptiveQoS_ROG.asp"),e.push("AiProtection_WebProtector.asp"),e.push("AdaptiveQoS_Bandwidth_Monitor.asp"),e.push("QoS_EZQoS.asp"),e.push("AdaptiveQoS_WebHistory.asp"),e.push("AdaptiveQoS_ROG.asp"),e.push("Advanced_QOSUserPrio_Content.asp"),e.push("Advanced_QOSUserRules_Content.asp"),e.push("AdaptiveQoS_Adaptive.asp"),e.push("TrafficAnalyzer_Statistic.asp"),e.push("AdaptiveQoS_TrafficLimiter.asp")),e}}();' "$TMP_WWW_DIR/require/modules/menuTree.js" && \
                    _applied=1

                if [ -n "$merlin" ]; then # but copy our modification to /tmp/menuTree.js and remount it
                    cp -f "$TMP_WWW_DIR/require/modules/menuTree.js" /tmp/menuTree.js
                    umount /www/require/modules/menuTree.js 2> /dev/null
                    mount --bind /tmp/menuTree.js /www/require/modules/menuTree.js
                else
                    mount --bind "$TMP_WWW_DIR/require/modules/menuTree.js" /www/require/modules/menuTree.js
                fi
            fi
        ;;
        "unset")
            if [ -n "$merlin" ] || [ -f /tmp/menuTree.js ]; then
                logecho "Unable to revert 'notrendmicro_support' tweak on Asuswrt-Merlin firmware - reboot is required!" error
                return
            fi

            if mount | grep -Fq /www/state.js; then
                umount /www/state.js
                rm -f "$TMP_WWW_DIR/state.js"
            fi

            if mount | grep -Fq /www/require/modules/menuTree.js; then
                umount /www/require/modules/menuTree.js
                rm -f "$TMP_WWW_DIR/require/modules/menuTree.js"
            fi
        ;;
    esac
    [ -z "$_applied" ] && return 1
}

https_lanport_allow_443() {
    _applied=
    case "$1" in
        "set")
            if ! mount | grep -Fq /www/Advanced_System_Content.asp; then
                [ ! -f "$TMP_WWW_DIR/Advanced_System_Content.asp" ] && cp -f /www/Advanced_System_Content.asp "$TMP_WWW_DIR/Advanced_System_Content.asp"

                sed_and_check replace '&& !validator.range(document.form.https_lanport, 1024, 65535) &&' "&& (document.form.https_lanport.value != 443 && !validator.range(document.form.https_lanport, 1024, 65535)) &&" "$TMP_WWW_DIR/Advanced_System_Content.asp" && \
                _applied=1

                mount --bind "$TMP_WWW_DIR/Advanced_System_Content.asp" /www/Advanced_System_Content.asp
            fi
        ;;
        "unset")
            if mount | grep -Fq /www/Advanced_System_Content.asp; then
                umount /www/Advanced_System_Content.asp
                rm -f "$TMP_WWW_DIR/Advanced_System_Content.asp"
            fi
        ;;
    esac
    [ -z "$_applied" ] && return 1
}

www_override() {
    case "$1" in
        "set")
            [ -z "$TWEAKS" ] && { logecho "Error: No tweaks to apply" error; exit 1; }

            mkdir -p "$TMP_WWW_DIR"

            applied=
            for tweak in $TWEAKS; do
                $tweak set && applied="$applied $tweak"
            done

            [ -n "$applied" ] && logecho "Applied WebUI tweaks: $(echo "$applied" | awk '{$1=$1};1')" alert
        ;;
        "unset")
            logecho "Removing WebUI tweaks..." alert

            cpu_temperature unset
            guest_wifi_qr_code unset
            notrendmicro_support unset
            https_lanport_allow_443 unset

            rm -fr "$TMP_WWW_DIR"
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
        sh "$script_path" stop
        sh "$script_path" start
    ;;
    *)
        echo "Usage: $0 start|stop|restart"
        exit 1
    ;;
esac
