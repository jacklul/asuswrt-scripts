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

TELEGRAM_BOT_TOKEN="" # Telegram bot token
TELEGRAM_CHAT_ID="" # Telegram chat identifier, can also be a group id or channel id/username
CACHE_FILE="/tmp/last_update_notify" # where to cache last notified version
CRON_MINUTE=0
CRON_HOUR="*/1"

if [ -f "$SCRIPT_CONFIG" ]; then
    #shellcheck disable=SC1090
    . "$SCRIPT_CONFIG"
fi

CURL_BINARY="curl"
[ -f /opt/bin/curl ] && CURL_BINARY="/opt/bin/curl"

send_telegram_message() {
    [ -z "$1" ] && { echo "Message not provided"; return 1; }

    RESULT=$($CURL_BINARY -fskSL --data chat_id="$TELEGRAM_CHAT_ID" --data "protect_content=true" --data "disable_web_page_preview=true" --data "parse_mode=HTML" --data "text=${1}" "https://api.telegram.org/bot${TELEGRAM_BOT_TOKEN}/sendMessage")

    if ! echo "$RESULT" | grep -q '"ok":true'; then
        if echo "$RESULT" | grep -q '"ok":'; then
            logger -st "$SCRIPT_TAG" "Telegram API error: $RESULT"
        else
            logger -st "$SCRIPT_TAG" "Connection to Telegram API failed: $RESULT"
        fi
    else
        return 0
    fi

    return 1
}

send_notification() {
    [ -z "$1" ] && { echo "Version not provided"; exit 1; }

    _NEW_VERSION="$1"

    ROUTER_IP="$(nvram get lan_ipaddr)"
    ROUTER_NAME="$(nvram get lan_hostname)"
    [ -z "$ROUTER_NAME" ] && ROUTER_NAME="$ROUTER_IP"

    if [ -n "$BOT_TOKEN" ] && [ -n "$CHAT_ID" ]; then
        logger -st "$SCRIPT_TAG" "Sending update notification through Telegram..."

        LINE_BREAK=$(printf '\n\r')
        MESSAGE="<b>New router firmware notification @ $ROUTER_NAME</b>${LINE_BREAK}${LINE_BREAK}New firmware version <b>$NEW_VERSION</b> is now available for your router."

        send_telegram_message "$MESSAGE"
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
        if cru l | grep -q "#$SCRIPT_NAME-test#"; then
            BUILDNO=$(nvram get buildno)
            EXTENDNO=$(nvram get extendno)

            if [ -n "$BUILDNO" ] && [ -n "$EXTENDNO" ]; then
                send_notification "${BUILDNO}_${EXTENDNO}"
            else
                logger -st "$SCRIPT_TAG" "Unable to obtain current version info"
            fi

            cru d "$SCRIPT_NAME-test"
        else
            cru a "$SCRIPT_NAME-test" "*/1 * * * * $SCRIPT_PATH test"
            echo "Scheduled a test with crontab, please wait one minute."
        fi
    ;;
    "start")
        { [ -z "$BOT_TOKEN" ] || [ -z "$CHAT_ID" ]; } && { logger -st "$SCRIPT_TAG" "Unable to start - configuration not set"; exit 1; }

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
