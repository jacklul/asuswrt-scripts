#!/bin/sh
# Made by Jack'lul <jacklul.github.io>
#
# Send update notification
#
# Based on:
#  https://github.com/RMerl/asuswrt-merlin.ng/wiki/Update-Notification-Example
#

#jas-update=update-notify.sh
#shellcheck disable=SC2155
#shellcheck source=./common.sh
readonly common_script="$(dirname "$0")/common.sh"
if [ -f "$common_script" ]; then . "$common_script"; else { echo "$common_script not found" >&2; exit 1; } fi

CRON="0 */6 * * *" # schedule as cron string
EMAIL_SMTP=""
EMAIL_PORT=""
EMAIL_USERNAME=""
EMAIL_PASSWORD=""
EMAIL_FROM_NAME=""
EMAIL_FROM_ADDRESS=""
EMAIL_TO_NAME=""
EMAIL_TO_ADDRESS=""
TELEGRAM_BOT_TOKEN=""
TELEGRAM_CHAT_ID=""
PUSHOVER_TOKEN=""
PUSHOVER_USERNAME=""
PUSHBULLET_TOKEN=""
CUSTOM_COMMAND="" # command will receive the new firmware version as its first parameter

load_script_config

state_file="$TMP_DIR/$script_name"
tmp_file="$TMP_DIR/$script_name.tmp"
router_ip="$(nvram get lan_ipaddr)"
router_name="$(nvram get lan_hostname)"
[ -z "$router_name" ] && router_name="$router_ip"
curl_binary="$(get_curl_binary)"
[ -z "$curl_binary" ] && { echo "curl not found"; exit 1; }

send_email_message() {
    cat <<EOT > "$tmp_file"
From: "$EMAIL_FROM_NAME" <$EMAIL_FROM_ADDRESS>
To: "$EMAIL_TO_NAME" <$EMAIL_TO_ADDRESS>
Subject: New router firmware notification @ $router_name
Content-Type: text/html; charset="utf-8"
Content-Transfer-Encoding: quoted-printable

New firmware version <b>$1</b> is now available for your router at <a href="$router_ip">$router_ip</a>.
EOT

    $curl_binary --url "smtps://$EMAIL_SMTP:$EMAIL_PORT" --mail-from "$EMAIL_FROM_ADDRESS" --mail-rcpt "$EMAIL_TO_ADDRESS" --upload-file "$tmp_file" --ssl-reqd --user "$EMAIL_USERNAME:$EMAIL_PASSWORD" || logecho "Failed to send an email message" error
    rm -f "$tmp_file"
}

send_telegram_message() {
    _linebreak=$(printf '\n\r')
    _message="<b>New router firmware notification @ $router_name</b>${_linebreak}${_linebreak}New firmware version <b>$1</b> is now available for your router at $router_ip."

    _result=$($curl_binary -fsS --data chat_id="$TELEGRAM_CHAT_ID" --data "protect_content=true" --data "disable_web_page_preview=true" --data "parse_mode=HTML" --data "text=$_message" "https://api.telegram.org/bot${TELEGRAM_BOT_TOKEN}/sendMessage")

    if ! echo "$_result" | grep -Fq '"ok":true'; then
        if echo "$_result" | grep -Fq '"ok":'; then
            logecho "Telegram API error: $_result" error
        else
            logecho "Connection to Telegram API failed: $_result" error
        fi
    fi
}

send_pushover_message() {
    $curl_binary --form-string "token=$PUSHOVER_TOKEN" --form-string "user=$PUSHOVER_USERNAME" --form-string "title=New router firmware notification @ $router_name" --form-string "message=New firmware version $1 is now available for your router at $router_ip." "https://api.pushover.net/1/messages.json" || logecho "Failed to send Pushover message" error
}

send_pushbullet_message () {
    $curl_binary -request POST --user "$PUSHBULLET_TOKEN": --header 'Content-Type: application/json' --data-binary '{"type": "note", "title": "'"New router firmware notification @ $router_name"'", "body": "'"New firmware version $1 is now available for your router at $router_ip."'"}' "https://api.pushbullet.com/v2/pushes" || logecho "Failed to send Pushbullet message" error
}

send_notification() {
    [ -z "$1" ] && { echo "Version not passed" >&2; exit 1; }

    if [ -n "$EMAIL_SMTP" ] && [ -n "$EMAIL_PORT" ] && [ -n "$EMAIL_USERNAME" ] && [ -n "$EMAIL_PASSWORD" ] && [ -n "$EMAIL_FROM_NAME" ] && [ -n "$EMAIL_FROM_ADDRESS" ] && [ -n "$EMAIL_TO_NAME" ] && [ -n "$EMAIL_TO_ADDRESS" ]; then
        logecho "Sending update notification through Email..."

        send_email_message "$1"
    fi

    if [ -n "$TELEGRAM_BOT_TOKEN" ] && [ -n "$TELEGRAM_CHAT_ID" ]; then
        logecho "Sending update notification through Telegram..."

        send_telegram_message "$1"
    fi

    if [ -n "$PUSHOVER_TOKEN" ] && [ -n "$PUSHOVER_USERNAME" ]; then
        logecho "Sending update notification through Pushover..."

        send_pushover_message "$1"
    fi

    if [ -n "$PUSHBULLET_TOKEN" ]; then
        logecho "Sending update notification through Pushbullet..."

        send_pushbullet_message "$1"
    fi

    if [ -n "$CUSTOM_COMMAND" ]; then
        logecho "Sending update notification through custom command..."

        $CUSTOM_COMMAND "$1"
    fi
}

check_and_notify() {
    { [ "$(nvram get wan0_state_t)" != "2" ] && [ "$(nvram get wan1_state_t)" != "2" ] ; } && { echo "WAN network is not connected" >&2; exit 1; }

    buildno=$(nvram get buildno)
    extendno=$(nvram get extendno)
    web_state_info=$(nvram get webs_state_info)
    web_buildno=$(echo "$web_state_info" | awk -F '_' '{print $2}' | sed 's/[-_.]*//g')
    #web_extendno_ver=$(echo "$web_state_info" | awk -F '_' '{print $3}' | awk -F '-' '{print $1}')

    if [ -z "$buildno" ] || [ -z "$extendno" ] || [ -z "$web_state_info" ] || [ "$buildno" -gt "$web_buildno" ]; then
        echo "Could not gather valid values from NVRAM" >&2
        exit 1
    fi

    new_version="$(echo "$web_state_info" | awk -F '_' '{print $2 "_" $3}')"
    current_version="${buildno}_${extendno}"

    if [ -n "$new_version" ] && [ "$current_version" != "$new_version" ] && { [ ! -f "$state_file" ] || [ "$(cat "$state_file")" != "$new_version" ] ; }; then
        send_notification "$new_version"

        echo "$new_version" > "$state_file"
    fi
}

case "$1" in
    "run")
        check_and_notify
    ;;
    "test")
        if { is_started_by_system && cru l | grep -Fq "#$script_name-test#"; } || [ "$2" = "now" ]; then
            logecho "Testing notification..." logger

            cru d "$script_name-test"

            buildno=$(nvram get buildno)
            extendno=$(nvram get extendno)

            if [ -n "$buildno" ] && [ -n "$extendno" ]; then
                send_notification "${buildno}_${extendno}"
            else
                logecho "Unable to obtain current version info" error
            fi
        else
            cru a "$script_name-test" "*/1 * * * * sh $script_path test"
            echo "Scheduled a test with crontab, please wait one minute."
        fi
    ;;
    "start")
        [ -n "$CRON" ] && crontab_entry add "$CRON $script_path run"
        check_and_notify
    ;;
    "stop")
        crontab_entry delete
    ;;
    "restart")
        sh "$script_path" stop
        sh "$script_path" start
    ;;
    *)
        echo "Usage: $0 run|start|stop|restart|test"
        exit 1
    ;;
esac
