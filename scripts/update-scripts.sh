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

SCRIPTS_PATH="/jffs/scripts" # path to scripts directory
BASE_DOWNLOAD_URL="https://raw.githubusercontent.com/jacklul/asuswrt-scripts/master/scripts" # base download url, no ending slash!

if [ -f "$SCRIPT_CONFIG" ]; then
    #shellcheck disable=SC1090
    . "$SCRIPT_CONFIG"
fi

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

[ -z "$1" ] && { sh "$SCRIPT_PATH" run; exit; }

case "$1" in
    "run")
        if echo "$SCRIPT_PATH" | grep -q "/tmp/"; then
            for ENTRY in "$SCRIPTS_PATH"/*.sh; do
                ENTRY="$(readlink -f "$ENTRY")"
                BASENAME="$(basename "$ENTRY")"

                echo "Processing '$ENTRY'..."
                download_and_check "$BASE_DOWNLOAD_URL/$BASENAME" "$ENTRY"

                #shellcheck disable=SC2002
                EXTRA_EXTENSIONS="$(cat "$ENTRY" | sed -n "s/^.*_FILE=.*\$SCRIPT_DIR\/\$SCRIPT_NAME\.\(.*\)\"\s#.*$/\1/p")"

                if [ -n "$EXTRA_EXTENSIONS" ]; then
                    ENTRY_NAME="$(basename "$ENTRY" .sh)"
                    ENTRY_DIR="$(dirname "$ENTRY")"
                    
                    IFS="$(printf '\n\b')"
                    for EXTENSION in $EXTRA_EXTENSIONS; do
                        echo "Processing '$ENTRY_DIR/$ENTRY_NAME.$EXTENSION'..."
                        download_and_check "$BASE_DOWNLOAD_URL/$ENTRY_NAME.$EXTENSION" "$ENTRY_DIR/$ENTRY_NAME.$EXTENSION"
                    done
                fi
            done
        else
            (
                cp "$0" "/tmp/$SCRIPT_NAME.sh"
                sh "/tmp/$SCRIPT_NAME.sh" run
                rm -f "/tmp/$SCRIPT_NAME.sh"
            )
        fi
    ;;
    *)
    ;;
esac
