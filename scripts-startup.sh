#!/bin/sh
# Made by Jack'lul <jacklul.github.io>
#
# This script starts all other scripts
#

#shellcheck disable=SC2155

readonly SCRIPT_PATH="$(readlink -f "$0")"
readonly SCRIPT_NAME="$(basename "$SCRIPT_PATH" .sh)"
readonly SCRIPT_DIR="$(dirname "$SCRIPT_PATH")"
readonly SCRIPT_CONFIG="$SCRIPT_DIR/$SCRIPT_NAME.conf"
readonly SCRIPT_TAG="$(basename "$SCRIPT_PATH")"

SCRIPTS_DIR="/jffs/scripts"
CHECK_FILE="/tmp/scripts_started"

if [ -f "$SCRIPT_CONFIG" ]; then
    #shellcheck disable=SC1090
    . "$SCRIPT_CONFIG"
fi

scripts() {
    readonly _ACTION="$1"

    for ENTRY in "$SCRIPTS_DIR"/*.sh; do
        [ "$(basename "$ENTRY" .sh)" = "$SCRIPT_NAME" ] && continue
        ! grep -q "\"start\")" "$ENTRY" && continue

        if [ -x "$ENTRY" ]; then
            ENTRY="$(readlink -f "$ENTRY")"

            case "$_ACTION" in
                "start")
                    logger -s -t "$SCRIPT_TAG" "Starting $ENTRY..."
                ;;
                "stop")
                    logger -s -t "$SCRIPT_TAG" "Stopping $ENTRY..."
                ;;
            esac

            /bin/sh "$ENTRY" "$_ACTION"
        fi
    done
}

case "$1" in
    "start")
        if [ ! -f "$CHECK_FILE" ]; then
            logger -s -t "$SCRIPT_TAG" "Starting custom scripts ($SCRIPTS_DIR)..."

            date > $CHECK_FILE

            scripts start
        fi
    ;;
    "stop")
        logger -s -t "$SCRIPT_TAG" "Stopping custom scripts ($SCRIPTS_DIR)..."

        rm -f "$CHECK_FILE"

        scripts stop
    ;;
    "install")
        if [ -f "/usr/sbin/helper.sh" ]; then
            logger -s -t "$SCRIPT_TAG" "Merlin firmware not supported, use /jffs/scripts/services-start script instead!"
            exit 1
        fi

        [ ! -x "$SCRIPT_PATH" ] && chmod +x "$SCRIPT_PATH"

        NVRAM_SCRIPT="/bin/sh $SCRIPT_PATH start"

        if [ "$(nvram get script_usbmount)" != "$NVRAM_SCRIPT" ]; then
            nvram set script_usbmount="$NVRAM_SCRIPT"
            nvram commit

            echo "Set nvram variable \"script_usbmount\" to \"$NVRAM_SCRIPT\""

            echo "Verifying that firmware does not unset the variable... (waiting 15 seconds before checking)"
            sleep 15

            if [ "$(nvram get script_usbmount)" = "$NVRAM_SCRIPT" ]; then
                echo "Everything looks good!"
            else
                echo "Failure - firmware erased the value!"
                echo "You will have to use a workaround - https://github.com/jacklul/asuswrt-scripts/master/asusware-usbmount"
            fi
        fi
    ;;
    *)
        echo "Usage: $0 start|stop|install"
        exit 1
    ;;
esac
