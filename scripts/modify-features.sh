#!/bin/sh
# Made by Jack'lul <jacklul.github.io>
#
# Modify features supported by the router (rc_support nvram variable)
#

# jacklul-asuswrt-scripts-update
#shellcheck disable=SC2155

readonly SCRIPT_PATH="$(readlink -f "$0")"
readonly SCRIPT_NAME="$(basename "$SCRIPT_PATH" .sh)"
readonly SCRIPT_DIR="$(dirname "$SCRIPT_PATH")"
readonly SCRIPT_CONFIG="$SCRIPT_DIR/$SCRIPT_NAME.conf"
readonly SCRIPT_TAG="$(basename "$SCRIPT_PATH")"

FEATURES_REMOVE="" # features to remove from the list
FEATURES_ADD="" # features to add to the list

if [ -f "$SCRIPT_CONFIG" ]; then
    #shellcheck disable=SC1090
    . "$SCRIPT_CONFIG"
fi

rc_support() {
    case "$1" in
        "modify")
            if [ ! -f /tmp/rc_support.bak ]; then
                RC_SUPPORT="$(nvram get rc_support)"
                echo "$RC_SUPPORT" > /tmp/rc_support.bak
            else
                RC_SUPPORT="$(cat /tmp/rc_support.bak)"
            fi

            if [ -f /tmp/rc_support.last ]; then
                RC_SUPPORT_LAST="$(cat /tmp/rc_support.last)"
            fi

            [ "$(nvram get rc_support)" = "$RC_SUPPORT_LAST" ] && exit

            for FEATURE_TO_REMOVE in $FEATURES_REMOVE; do
                if echo "$RC_SUPPORT" | grep -q "$FEATURE_TO_REMOVE"; then
                    RC_SUPPORT="$(echo "$RC_SUPPORT" | sed "s/$FEATURE_TO_REMOVE//g")"
                fi
            done

            for FEATURE_TO_ADD in $FEATURES_ADD; do
                if ! echo "$RC_SUPPORT" | grep -q "$FEATURE_TO_ADD"; then
                    RC_SUPPORT="$RC_SUPPORT $FEATURE_TO_ADD"
                fi
            done

            RC_SUPPORT="$(echo "$RC_SUPPORT" | tr -s ' ')"

            echo "$RC_SUPPORT" > /tmp/rc_support.last

            nvram set rc_support="$RC_SUPPORT"

            logger -st "$SCRIPT_TAG" "Modified rc_support"
        ;;
        "restore")
            rm -f /tmp/rc_support.last

            if [ -f /tmp/rc_support.bak ]; then
                RC_SUPPORT="$(cat /tmp/rc_support.bak)"

                nvram set rc_support="$RC_SUPPORT"

                logger -st "$SCRIPT_TAG" "Restored original rc_support"
            else
                logger -st "$SCRIPT_TAG" "Could not find /tmp/rc_support.bak - cannot restore original rc_support!"
            fi
        ;;
    esac
}

case "$1" in
    "run")
        [ -z "$FEATURES_REMOVE" ] && [ -z "$FEATURES_ADD" ] && exit

        rc_support modify
    ;;
    "start")
        if [ -z "$FEATURES_REMOVE" ] || [ -z "$FEATURES_ADD" ]; then
            logger -st "$SCRIPT_TAG" "Configuration is not set"
        fi

        if [ -x "$SCRIPT_DIR/cron-queue.sh" ]; then
            "$SCRIPT_DIR/cron-queue.sh" add "$SCRIPT_NAME" "$SCRIPT_PATH run"
        else
            cru a "$SCRIPT_NAME" "*/1 * * * * $SCRIPT_PATH run"
        fi

        rc_support modify
    ;;
    "stop")
        [ -x "$SCRIPT_DIR/cron-queue.sh" ] && "$SCRIPT_DIR/cron-queue.sh" remove "$SCRIPT_NAME"
        cru d "$SCRIPT_NAME"

        rc_support restore
    ;;
    "restart")
        sh "$SCRIPT_PATH" stop
        sh "$SCRIPT_PATH" start
    ;;
    *)
        echo "Usage: $0 run|start|stop|restart"
        exit 1
    ;;
esac
