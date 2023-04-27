#!/bin/sh
# Made by Jack'lul <jacklul.github.io>
#
# Update all installed scripts
#
# For security and reliability reasons this cannot be run at boot
#

#shellcheck disable=SC2155

SCRIPTS_PATH="/jffs/scripts" # path to scripts directory
BASE_DOWNLOAD_URL="https://raw.githubusercontent.com/jacklul/asuswrt-scripts/master/scripts" # base download url, no ending slash!

readonly SCRIPT_NAME="$(basename "$0" .sh)"
readonly SCRIPT_PATH="$(readlink -f "$0")"
readonly SCRIPT_CONFIG="$(dirname "$0")/$SCRIPT_NAME.conf"
if [ -f "$SCRIPT_CONFIG" ]; then
    #shellcheck disable=SC1090
    . "$SCRIPT_CONFIG"
fi

md5_compare() {
    if [ -n "$1" ] && [ -n "$2" ]; then
        if [ "$(md5sum "$1" | awk '{print $1}')" = "$(md5sum "$2" | awk '{print $1}')" ]; then
            return 0
        fi
    fi

    return 1
}

download_and_check() {
    if [ -n "$1" ] && [ -n "$2" ]; then
        if curl -sf "$1" -o "/tmp/$SCRIPT_NAME-download"; then
            if ! md5_compare "/tmp/$SCRIPT_NAME-download" "$2"; then
                [ -x "$SCRIPT_PATH" ] && logger -s -t "$SCRIPT_NAME" "Updating '$2'..." || echo "Updating '$2'..."

                cat "/tmp/$SCRIPT_NAME-download" > "$2"
                [ -x "$SCRIPT_PATH" ] && [ -x "$2" ] && sh "$2" restart
            fi
        else
            echo "Failed to download from url '$1'"
        fi

        rm -f "/tmp/$SCRIPT_NAME-download"
    fi
}

case "$1" in
    "run")
        if echo "$SCRIPT_PATH" | grep -q "/tmp/"; then
            for ENTRY in "$SCRIPTS_PATH"/*.sh; do
                ENTRY="$(readlink -f "$ENTRY")"
                BASENAME="$(basename "$ENTRY")"

                echo "Processing '$BASENAME'..."
                download_and_check "$BASE_DOWNLOAD_URL/$BASENAME" "$ENTRY"
            done
        else
            (
                cp "$0" "/tmp/$SCRIPT_NAME.sh"
                sh "/tmp/$SCRIPT_NAME.sh" run
                rm -f "/tmp/$SCRIPT_NAME.sh"
            )
        fi
    ;;
    "start"|"stop"|"restart")
        echo "Unsupported"
    ;;
    *)
        sh "$SCRIPT_PATH" run
    ;;
esac
