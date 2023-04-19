#!/bin/sh
# Made by Jack'lul <jacklul.github.io>

#shellcheck disable=SC2155

SCRIPTS_PATH="/jffs/scripts"
CHECK_FILE="/tmp/scripts_started"

readonly SCRIPT_NAME="$(basename "$0" .sh)"
readonly SCRIPT_PATH="$(readlink -f "$0")"
readonly SCRIPT_CONFIG="$(dirname "$0")/$SCRIPT_NAME.conf"
if [ -f "$SCRIPT_CONFIG" ]; then
    #shellcheck disable=SC1090
    . "$SCRIPT_CONFIG"
fi

scripts() {
    readonly _ACTION="$1"

    for ENTRY in "$SCRIPTS_PATH"/*; do
        [ "$(basename "$ENTRY" .sh)" = "$SCRIPT_NAME" ] && continue

        if [ -x "$ENTRY" ]; then
            ENTRY="$(readlink -f "$ENTRY")"

            case "$_ACTION" in
                "start")
                    logger -s -t "$SCRIPT_NAME" "Starting $ENTRY..."
                ;;
                "stop")
                    logger -s -t "$SCRIPT_NAME" "Stopping $ENTRY..."
                ;;
            esac

            /bin/sh "$ENTRY" "$_ACTION"
        fi
    done
}

case "$1" in
    "start")
        if [ ! -f "$CHECK_FILE" ]; then
            logger -s -t "$SCRIPT_NAME" "Starting user scripts..."

            date > $CHECK_FILE

            scripts start
        fi
    ;;
    "stop")
        logger -s -t "$SCRIPT_NAME" "Stopping user scripts..."

        scripts stop

        rm "$CHECK_FILE"
    ;;
    "install")
        [ ! -d "$SCRIPTS_PATH" ] && mkdir -v "$SCRIPTS_PATH"
        [ ! -x "$SCRIPT_PATH" ] && chmod +x "$SCRIPT_PATH"

        NVRAM_SCRIPT="/bin/sh $SCRIPT_PATH start"

        if [ "$(nvram get script_usbmount)" != "$NVRAM_SCRIPT" ]; then
            nvram set script_usbmount="$NVRAM_SCRIPT"
            nvram commit

            echo "Set nvram variable \"script_usbmount\" to \"$NVRAM_SCRIPT\""
        fi
    ;;
    *)
        echo "Usage: $0 start|stop|install"
        exit 1
    ;;
esac
