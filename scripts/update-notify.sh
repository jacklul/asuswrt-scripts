#!/bin/sh
# Made by Jack'lul <jacklul.github.io>
#
# Sends update notification
#
# Based on:
#  https://github.com/RMerl/asuswrt-merlin.ng/wiki/Update-Notification-Example
#

#jacklul-asuswrt-scripts-update=update-notify.sh
#shellcheck disable=SC2155

readonly script_path="$(readlink -f "$0")"
readonly script_name="$(basename "$script_path" .sh)"
readonly script_dir="$(dirname "$script_path")"
readonly script_config="$script_dir/$script_name.conf"

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
CACHE_FILE="/tmp/last_update_notify" # where to cache last notified version
CRON="0 */6 * * *" # schedule as cron string

umask 022 # set default umask

if [ -f "$script_config" ]; then
    #shellcheck disable=SC1090
    . "$script_config"
fi

router_ip="$(nvram get lan_ipaddr)"
router_name="$(nvram get lan_hostname)"
[ -z "$router_name" ] && router_name="$router_ip"
curl_binary="curl"
[ -f /opt/bin/curl ] && curl_binary="/opt/bin/curl" # prefer Entware's curl as it is not modified by Asus

is_started_by_system() { #ISSTARTEDBYSYSTEM_START#
    _ppid=$PPID
    while true; do
        [ -z "$_ppid" ] && break
        _ppid=$(< "/proc/$_ppid/stat" awk '{print $4}')
        grep -Fq "cron" "/proc/$_ppid/comm" && return 0
        grep -Fq "hotplug" "/proc/$_ppid/comm" && return 0
        [ "$_ppid" -gt 1 ] || break
    done
    return 1
} #ISSTARTEDBYSYSTEM_END#

send_email_message() {
    cat <<EOT > /tmp/mail.eml
From: "$EMAIL_FROM_NAME" <$EMAIL_FROM_ADDRESS>
To: "$EMAIL_TO_NAME" <$EMAIL_TO_ADDRESS>
Subject: New router firmware notification @ $router_name
Content-Type: text/html; charset="utf-8"
Content-Transfer-Encoding: quoted-printable

New firmware version <b>$1</b> is now available for your router at <a href="$router_ip">$router_ip</a>.
EOT

    curl --url "smtps://$EMAIL_SMTP:$EMAIL_PORT" --mail-from "$EMAIL_FROM_ADDRESS" --mail-rcpt "$EMAIL_TO_ADDRESS" --upload-file /tmp/mail.eml --ssl-reqd --user "$EMAIL_USERNAME:$EMAIL_PASSWORD" || logger -st "$script_name" "Failed to send an email message"
    rm -f /tmp/mail.eml
}

send_telegram_message() {
    _linebreak=$(printf '\n\r')
    _message="<b>New router firmware notification @ $router_name</b>${_linebreak}${_linebreak}New firmware version <b>$1</b> is now available for your router at $router_ip."

    _result=$($curl_binary -fsS --data chat_id="$TELEGRAM_CHAT_ID" --data "protect_content=true" --data "disable_web_page_preview=true" --data "parse_mode=HTML" --data "text=$_message" "https://api.telegram.org/bot${TELEGRAM_BOT_TOKEN}/sendMessage")

    if ! echo "$_result" | grep -Fq '"ok":true'; then
        if echo "$_result" | grep -Fq '"ok":'; then
            logger -st "$script_name" "Telegram API error: $_result"
        else
            logger -st "$script_name" "Connection to Telegram API failed: $_result"
        fi
    fi
}

send_pushover_message() {
    curl --form-string "token=$PUSHOVER_TOKEN" --form-string "user=$PUSHOVER_USERNAME" --form-string "title=New router firmware notification @ $router_name" --form-string "message=New firmware version $1 is now available for your router at $router_ip." "https://api.pushover.net/1/messages.json" || logger -st "$script_name" "Failed to send Pushover message"
}

send_pushbullet_message () {
    curl -request POST --user "$PUSHBULLET_TOKEN": --header 'Content-Type: application/json' --data-binary '{"type": "note", "title": "'"New router firmware notification @ $router_name"'", "body": "'"New firmware version $1 is now available for your router at $router_ip."'"}' "https://api.pushbullet.com/v2/pushes" || logger -st "$script_name" "Failed to send Pushbullet message"
}

send_notification() {
    [ -z "$1" ] && { echo "Version not provided"; exit 1; }

    if [ -n "$EMAIL_SMTP" ] && [ -n "$EMAIL_PORT" ] && [ -n "$EMAIL_USERNAME" ] && [ -n "$EMAIL_PASSWORD" ] && [ -n "$EMAIL_FROM_NAME" ] && [ -n "$EMAIL_FROM_ADDRESS" ] && [ -n "$EMAIL_TO_NAME" ] && [ -n "$EMAIL_TO_ADDRESS" ]; then
        logger -st "$script_name" "Sending update notification through Email..."

        send_email_message "$1"
    fi

    if [ -n "$TELEGRAM_BOT_TOKEN" ] && [ -n "$TELEGRAM_CHAT_ID" ]; then
        logger -st "$script_name" "Sending update notification through Telegram..."

        send_telegram_message "$1"
    fi

    if [ -n "$PUSHOVER_TOKEN" ] && [ -n "$PUSHOVER_USERNAME" ]; then
        logger -st "$script_name" "Sending update notification through Pushover..."

        send_pushover_message "$1"
    fi

    if [ -n "$PUSHBULLET_TOKEN" ]; then
        logger -st "$script_name" "Sending update notification through Pushbullet..."

        send_pushbullet_message "$1"
    fi

    if [ -n "$CUSTOM_COMMAND" ]; then
        logger -st "$script_name" "Sending update notification through custom command..."

        $CUSTOM_COMMAND "$1"
    fi
}

case "$1" in
    "run")
        { [ "$(nvram get wan0_state_t)" != "2" ] && [ "$(nvram get wan1_state_t)" != "2" ] ; } && { echo "WAN network is not connected"; exit 1; }

        buildno=$(nvram get buildno | sed 's/[-_.]*//g')
        extendno=$(nvram get extendno)
        web_state_info=$(nvram get webs_state_info)

        #extendno_ver=$(echo "$extendno" | awk -F '-' '{print $1}')
        web_buildno=$(echo "$web_state_info" | awk -F '_' '{print $2}' | sed 's/[-_.]*//g')
        #web_extendno_ver=$(echo "$web_state_info" | awk -F '_' '{print $3}' | awk -F '-' '{print $1}')

        if [ -z "$buildno" ] || [ -z "$extendno" ] || [ -z "$web_state_info" ] ||  [ "$buildno" -gt "$web_buildno" ]; then
            echo "Could not gather valid values from NVRAM"
            exit
        fi

        new_version="$(echo "$web_state_info" | awk -F '_' '{print $2 "_" $3}')"
        current_version="${buildno}_${extendno}"

        if [ -n "$new_version" ] && [ "$current_version" != "$new_version" ] && { [ ! -f "$CACHE_FILE" ] || [ "$(cat "$CACHE_FILE")" != "$new_version" ] ; }; then
            send_notification "$new_version"

            echo "$new_version" > "$CACHE_FILE"
        fi
    ;;
    "test")
        if { is_started_by_system && cru l | grep -Fq "#$script_name-test#"; } || [ "$2" = "now" ]; then
            logger -st "$script_name" "Testing notification..."

            cru d "$script_name-test"

            buildno=$(nvram get buildno)
            extendno=$(nvram get extendno)

            if [ -n "$buildno" ] && [ -n "$extendno" ]; then
                send_notification "${buildno}_${extendno}"
            else
                logger -st "$script_name" "Unable to obtain current version info"
            fi
        else
            cru a "$script_name-test" "*/1 * * * * sh $script_path test"
            echo "Scheduled a test with crontab, please wait one minute."
        fi
    ;;
    "start")
        cru a "$script_name" "$CRON $script_path run"

        sh "$script_path" run &
    ;;
    "stop")
        [ -x "$script_dir/cron-queue.sh" ] && sh "$script_dir/cron-queue.sh" remove "$script_name"
        cru d "$script_name"
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
