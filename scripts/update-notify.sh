#!/bin/sh
# Made by Jack'lul <jacklul.github.io>
#
# Sends update notification through Telegram
#

#shellcheck disable=SC2155

BOT_TOKEN="" # Telegram bot token
CHAT_ID="" # Telegram chat identifier, can also be a group id or channel id/username
CACHE_FILE="/tmp/last_update_notify" # where to cache last notified version
CRON_MINUTE=0
CRON_HOUR="*/1"

# This means that this is a Merlin firmware
if [ -f "/usr/sbin/helper.sh" ]; then
    #shellcheck disable=SC1091
    . /usr/sbin/helper.sh

    BOT_TOKEN_=$(am_settings_get jl_unotify_bot_token)
    CHAT_ID_=$(am_settings_get jl_unotify_chat_id)

    [ -n "$BOT_TOKEN_" ] && BOT_TOKEN=$BOT_TOKEN_
    [ -n "$CHAT_ID_" ] && CHAT_ID=$CHAT_ID_
fi

readonly SCRIPT_NAME="$(basename "$0" .sh)"
readonly SCRIPT_PATH="$(readlink -f "$0")"
readonly SCRIPT_CONFIG="$(dirname "$0")/$SCRIPT_NAME.conf"
if [ -f "$SCRIPT_CONFIG" ]; then
    #shellcheck disable=SC1090
    . "$SCRIPT_CONFIG"
fi

NOTIFICATION_SENT=0

case "$1" in
    "run")
        { [ "$(nvram get wan0_state_t)" != "2" ] && [ "$(nvram get wan1_state_t)" != "2" ]; } && { echo "WAN network is not connected"; exit 1; }

        BUILDNO=$(nvram get buildno)
        EXTENDNO=$(nvram get extendno)
        WEBS_STATE_INFO=$(nvram get webs_state_info)

        if [ -z "$BUILDNO" ] || [ -z "$EXTENDNO" ] || [ -z "$WEBS_STATE_INFO" ]; then
            exit
        fi

        NEW_VERSION="$(echo "$WEBS_STATE_INFO" | awk -F '_' '{print $2 "_" $3}')"
        CURRENT_VERSION="${BUILDNO}_${EXTENDNO}"

        if [ -n "$NEW_VERSION" ] && [ "$CURRENT_VERSION" != "$NEW_VERSION" ] && { [ ! -f "$CACHE_FILE" ] || [ "$(cat "$CACHE_FILE")" != "$NEW_VERSION" ]; }; then
            if [ -n "$BOT_TOKEN" ] && [ -n "$CHAT_ID" ]; then
                logger -s -t "$SCRIPT_NAME" "Sending update notification through Telegram..."

                LINE_BREAK=$(printf '\n\r')
                ROUTER_IP="$(nvram get lan_ipaddr)"
                ROUTER_NAME="$(nvram get lan_hostname)"

                [ -z "$ROUTER_NAME" ] && ROUTER_NAME="$ROUTER_IP"

                MESSAGE="<b>New router firmware notification @ $ROUTER_NAME</b>${LINE_BREAK}${LINE_BREAK}New firmware version <b>$NEW_VERSION</b> is now available for your router."

                RESULT=$(curl --silent --insecure --data chat_id="$CHAT_ID" --data "protect_content=true" --data "disable_web_page_preview=true" --data "parse_mode=HTML" --data "text=${MESSAGE}" "https://api.telegram.org/bot$BOT_TOKEN/sendMessage")

                if ! echo "$RESULT" | grep -q '"ok":true'; then
                    if echo "$RESULT" | grep -q '"ok":'; then
                        logger -s -t "$SCRIPT_NAME" "Telegram API error: $RESULT"
                    else
                        logger -s -t "$SCRIPT_NAME" "Connection to Telegram API failed"
                    fi
                else
                    NOTIFICATION_SENT=1
                fi
            else
                logger -s -t "$SCRIPT_NAME" "Unable to execute - either BOT TOKEN or CHAT ID are not set"
            fi

            [ "$NOTIFICATION_SENT" = "1" ] && echo "$NEW_VERSION" > "$CACHE_FILE"
        fi
    ;;
    "start")
        { [ -z "$BOT_TOKEN" ] || [ -z "$CHAT_ID" ]; } && { logger -s -t "$SCRIPT_NAME" "Unable to start - configuration not set"; exit 1; }

        cru a "$SCRIPT_NAME" "$CRON_MINUTE $CRON_HOUR * * * $SCRIPT_PATH run"

        sh "$SCRIPT_PATH" run &
    ;;
    "stop")
        cru d "$SCRIPT_NAME"
    ;;
    *)
        echo "Usage: $0 run|start|stop"
        exit 1
    ;;
esac
