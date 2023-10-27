#!/bin/sh
# Made by Jack'lul <jacklul.github.io>
#
# Update all installed scripts
#
# For security and reliability reasons this cannot be run at boot
#

#shellcheck disable=SC2155

readonly SCRIPT_PATH="$(readlink -f "$0")"
readonly SCRIPT_NAME="$(basename "$SCRIPT_PATH" .sh)"
readonly SCRIPT_DIR="$(dirname "$SCRIPT_PATH")"
readonly SCRIPT_CONFIG="$SCRIPT_DIR/$SCRIPT_NAME.conf"
readonly SCRIPT_TAG="$(basename "$SCRIPT_PATH")"

SCRIPTS_PATH="/jffs/scripts" # path to scripts directory
BRANCH="master" # which git branch to use
BASE_URL="https://raw.githubusercontent.com/jacklul/asuswrt-scripts" # base download url, no ending slash!
BASE_PATH="scripts" # base path to scripts directory in the download URL, no slash on either side

if [ -f "$SCRIPT_CONFIG" ]; then
    #shellcheck disable=SC1090
    . "$SCRIPT_CONFIG"
fi

DOWNLOAD_URL="$BASE_URL/$BRANCH/$BASE_PATH"

md5_compare() {
    { [ ! -f "$1" ] || [ ! -f "$2" ]; } && return 1

    if [ -n "$1" ] && [ -n "$2" ]; then
        if [ "$(md5sum "$1" | awk '{print $1}')" = "$(md5sum "$2" | awk '{print $1}')" ]; then
            return 0
        fi
    fi

    return 1
}

download_and_check() {
    if [ -n "$1" ] && [ -n "$2" ]; then
        if curl -fsSL "$1" -o "/tmp/$SCRIPT_NAME-download"; then
            if ! md5_compare "/tmp/$SCRIPT_NAME-download" "$2"; then
                [ -x "$SCRIPT_PATH" ] && logger -st "$SCRIPT_TAG" "Updating '$2'..." || echo "Updating '$2'..."

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
        for ENTRY in "$SCRIPTS_PATH"/*.sh; do
            ENTRY="$(readlink -f "$ENTRY")"
            BASENAME="$(basename "$ENTRY")"

            grep -q "SCRIPT_ARCHIVED=true" "$ENTRY" && continue

            echo "Processing '$ENTRY'..."
            download_and_check "$DOWNLOAD_URL/$BASENAME" "$ENTRY"

            #shellcheck disable=SC2002
            EXTRA_EXTENSIONS="$(cat "$ENTRY" | sed -n "s/^.*_FILE=.*\$SCRIPT_DIR\/\$SCRIPT_NAME\.\(.*\)\"\s#.*$/\1/p")"

            if [ -n "$EXTRA_EXTENSIONS" ]; then
                ENTRY_NAME="$(basename "$ENTRY" .sh)"
                ENTRY_DIR="$(dirname "$ENTRY")"

                IFS="$(printf '\n\b')"
                for EXTENSION in $EXTRA_EXTENSIONS; do
                    echo "Processing '$ENTRY_DIR/$ENTRY_NAME.$EXTENSION'..."
                    download_and_check "$DOWNLOAD_URL/$ENTRY_NAME.$EXTENSION" "$ENTRY_DIR/$ENTRY_NAME.$EXTENSION"
                done
            fi
        done
    ;;
    *)
        echo "Usage: $0 run"
        exit 1
    ;;
esac
