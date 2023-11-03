#!/bin/sh
# Made by Jack'lul <jacklul.github.io>
#
# Sends update notification
#
# Currently only Telegram is supported
#
# Based on:
#  https://github.com/RMerl/asuswrt-merlin.ng/wiki/Update-Notification-Example
#

#shellcheck disable=SC2155

readonly SCRIPT_PATH="$(readlink -f "$0")"
readonly SCRIPT_NAME="$(basename "$SCRIPT_PATH" .sh)"
readonly SCRIPT_DIR="$(dirname "$SCRIPT_PATH")"
readonly SCRIPT_CONFIG="$SCRIPT_DIR/$SCRIPT_NAME.conf"
readonly SCRIPT_TAG="$(basename "$SCRIPT_PATH")"

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
CACHE_FILE="/tmp/last_update_notify" # where to cache last notified version
CRON_MINUTE=0
CRON_HOUR="*/1"

if [ -f "$SCRIPT_CONFIG" ]; then
    #shellcheck disable=SC1090
    . "$SCRIPT_CONFIG"
fi

ROUTER_IP="$(nvram get lan_ipaddr)"
ROUTER_NAME="$(nvram get lan_hostname)"
[ -z "$ROUTER_NAME" ] && ROUTER_NAME="$ROUTER_IP"
CURL_BINARY="curl"
[ -f /opt/bin/curl ] && CURL_BINARY="/opt/bin/curl"

is_started_by_system() { #ISSTARTEDBYSYSTEM_START#
    _PPID=$PPID
    while true; do
        [ -z "$_PPID" ] && break
        _PPID=$(< "/proc/$_PPID/stat" awk '{print $4}')

        grep -q "cron" "/proc/$_PPID/comm" && return 0
        grep -q "hotplug" "/proc/$_PPID/comm" && return 0
        [ "$_PPID" -gt "1" ] || break
    done

    return 1
} #STARTEDBYSYSTEMFUNC_END#

send_email_message() {
    cat <<EOT > /tmp/mail.eml
From: "$EMAIL_FROM_NAME" <$EMAIL_FROM_ADDRESS>
To: "$EMAIL_TO_NAME" <$EMAIL_TO_ADDRESS>
Subject: New router firmware notification @ $ROUTER_NAME
Content-Type: text/html; charset="utf-8"
Content-Transfer-Encoding: quoted-printable

New firmware version <b>$1</b> is now available for your router at <a href="$ROUTER_IP">$ROUTER_IP</a>.
EOT

    curl --url "smtps://$EMAIL_SMTP:$EMAIL_PORT" --mail-from "$EMAIL_FROM_ADDRESS" --mail-rcpt "$EMAIL_TO_ADDRESS" --upload-file /tmp/mail.eml --ssl-reqd --user "$EMAIL_USERNAME:$EMAIL_PASSWORD" || logger -st "$SCRIPT_TAG" "Failed to send an email message"
    rm -f /tmp/mail.eml
}

send_telegram_message() {
    _LINE_BREAK=$(printf '\n\r')
    _MESSAGE="<b>New router firmware notification @ $ROUTER_NAME</b>${_LINE_BREAK}${_LINE_BREAK}New firmware version <b>$1</b> is now available for your router at $ROUTER_IP."

    RESULT=$($CURL_BINARY -fsS --data chat_id="$TELEGRAM_CHAT_ID" --data "protect_content=true" --data "disable_web_page_preview=true" --data "parse_mode=HTML" --data "text=$_MESSAGE" "https://api.telegram.org/bot${TELEGRAM_BOT_TOKEN}/sendMessage")

    if ! echo "$RESULT" | grep -q '"ok":true'; then
        if echo "$RESULT" | grep -q '"ok":'; then
            logger -st "$SCRIPT_TAG" "Telegram API error: $RESULT"
        else
            logger -st "$SCRIPT_TAG" "Connection to Telegram API failed: $RESULT"
        fi
    fi
}

send_pushover_message() {
    curl --form-string "token=$PUSHOVER_TOKEN" --form-string "user=$PUSHOVER_USERNAME" --form-string "title=New router firmware notification @ $ROUTER_NAME" --form-string "message=New firmware version $1 is now available for your router at $ROUTER_IP." "https://api.pushover.net/1/messages.json" || logger -st "$SCRIPT_TAG" "Failed to send Pushover message"
}

send_pushbullet_message () {
    curl -request POST --user "$PUSHBULLET_TOKEN": --header 'Content-Type: application/json' --data-binary '{"type": "note", "title": "'"New router firmware notification @ $ROUTER_NAME"'", "body": "'"New firmware version $1 is now available for your router at $ROUTER_IP."'"}' "https://api.pushbullet.com/v2/pushes" || logger -st "$SCRIPT_TAG" "Failed to send Pushbullet message"
}

send_notification() {
    [ -z "$1" ] && { echo "Version not provided"; exit 1; }

    if [ -n "$EMAIL_SMTP" ] && [ -n "$EMAIL_PORT" ] && [ -n "$EMAIL_USERNAME" ] && [ -n "$EMAIL_PASSWORD" ] && [ -n "$EMAIL_FROM_NAME" ] && [ -n "$EMAIL_FROM_ADDRESS" ] && [ -n "$EMAIL_TO_NAME" ] && [ -n "$EMAIL_TO_ADDRESS" ]; then
        logger -st "$SCRIPT_TAG" "Sending update notification through Email..."

        send_email_message "$1"
    fi

    if [ -n "$TELEGRAM_BOT_TOKEN" ] && [ -n "$TELEGRAM_CHAT_ID" ]; then
        logger -st "$SCRIPT_TAG" "Sending update notification through Telegram..."

        send_telegram_message "$1"
    fi

    if [ -n "$PUSHOVER_TOKEN" ] && [ -n "$PUSHOVER_USERNAME" ]; then
        logger -st "$SCRIPT_TAG" "Sending update notification through Pushover..."

        send_pushover_message "$1"
    fi

    if [ -n "$PUSHBULLET_TOKEN" ]; then
        logger -st "$SCRIPT_TAG" "Sending update notification through Pushbullet..."

        send_pushbullet_message "$1"
    fi
}

case "$1" in
    "run")
        { [ "$(nvram get wan0_state_t)" != "2" ] && [ "$(nvram get wan1_state_t)" != "2" ]; } && { echo "WAN network is not connected"; exit 1; }

        BUILDNO=$(nvram get buildno)
        EXTENDNO=$(nvram get extendno)
        WEBS_STATE_INFO=$(nvram get webs_state_info)

        EXTENDNO_VER=$(echo "$EXTENDNO" | awk -F '-' '{print $1}')
        WEBS_BUILDNO=$(echo "$WEBS_STATE_INFO" | awk -F '_' '{print $2}')
        WEBS_EXTENDNO_VER=$(echo "$WEBS_STATE_INFO" | awk -F '_' '{print $3}' | awk -F '-' '{print $1}')

        if [ -z "$BUILDNO" ] || [ -z "$EXTENDNO" ] || [ -z "$WEBS_STATE_INFO" ] ||  [ "$BUILDNO" -gt "$WEBS_BUILDNO" ] || [ "$EXTENDNO_VER" -gt "$WEBS_EXTENDNO_VER" ]; then
            echo "Could not gather valid values from NVRAM"
            exit
        fi

        NEW_VERSION="$(echo "$WEBS_STATE_INFO" | awk -F '_' '{print $2 "_" $3}')"
        CURRENT_VERSION="${BUILDNO}_${EXTENDNO}"

        if [ -n "$NEW_VERSION" ] && [ "$CURRENT_VERSION" != "$NEW_VERSION" ] && { [ ! -f "$CACHE_FILE" ] || [ "$(cat "$CACHE_FILE")" != "$NEW_VERSION" ]; }; then
            send_notification "$NEW_VERSION"

            echo "$NEW_VERSION" > "$CACHE_FILE"
        fi
    ;;
    "test")
        if { is_started_by_system || [ "$2" = "now" ]; } && cru l | grep -q "#$SCRIPT_NAME-test#"; then
            logger -st "$SCRIPT_TAG" "Testing notification..."

            cru d "$SCRIPT_NAME-test"

            BUILDNO=$(nvram get buildno)
            EXTENDNO=$(nvram get extendno)

            if [ -n "$BUILDNO" ] && [ -n "$EXTENDNO" ]; then
                send_notification "${BUILDNO}_${EXTENDNO}"
            else
                logger -st "$SCRIPT_TAG" "Unable to obtain current version info"
            fi
        else
            cru a "$SCRIPT_NAME-test" "*/1 * * * * sh $SCRIPT_PATH test"
            echo "Scheduled a test with crontab, please wait one minute."
        fi
    ;;
    "start")
        cru a "$SCRIPT_NAME" "$CRON_MINUTE $CRON_HOUR * * * $SCRIPT_PATH run"

        sh "$SCRIPT_PATH" run &
    ;;
    "stop")
        cru d "$SCRIPT_NAME"
    ;;
    "restart")
        sh "$SCRIPT_PATH" stop
        sh "$SCRIPT_PATH" start
    ;;
    *)
        echo "Usage: $0 run|start|stop|restart|test"
        exit 1
    ;;
esac
