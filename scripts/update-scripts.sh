#!/bin/sh
# Made by Jack'lul <jacklul.github.io>
#
# Update all installed scripts
#
# For security and reliability reasons this cannot be run at boot
#

#jacklul-asuswrt-scripts-update=update-scripts.sh
#shellcheck disable=SC2155

readonly SCRIPT_PATH="$(readlink -f "$0")"
readonly SCRIPT_NAME="$(basename "$SCRIPT_PATH" .sh)"
readonly SCRIPT_DIR="$(dirname "$SCRIPT_PATH")"
readonly SCRIPT_CONFIG="$SCRIPT_DIR/$SCRIPT_NAME.conf"

BRANCH="master" # which git branch to use
BASE_URL="https://raw.githubusercontent.com/jacklul/asuswrt-scripts" # base download url, no ending slash!
BASE_PATH="scripts" # base path to scripts directory in the download URL, no slash on either side
AUTOUPDATE=true # whenever to auto-update this script first or not

if [ -f "$SCRIPT_CONFIG" ]; then
    #shellcheck disable=SC1090
    . "$SCRIPT_CONFIG"
fi

DOWNLOAD_URL="$BASE_URL/$BRANCH/$BASE_PATH"
CURL_BINARY="curl"
[ -f /opt/bin/curl ] && CURL_BINARY="/opt/bin/curl"

md5_compare() {
    { [ ! -f "$1" ] || [ ! -f "$2" ]; } && return 1

    if [ -n "$1" ] && [ -n "$2" ]; then
        if [ "$(md5sum "$1" 2> /dev/null | awk '{print $1}')" = "$(md5sum "$2" 2> /dev/null | awk '{print $1}')" ]; then
            return 0
        fi
    fi

    return 1
}

download_and_check() {
    if [ -n "$1" ] && [ -n "$2" ]; then
        if $CURL_BINARY -fsSL "$1?$(date +%s)" -o "/tmp/$SCRIPT_NAME-download"; then
            if ! md5_compare "/tmp/$SCRIPT_NAME-download" "$2"; then
                return 0
            fi
        else
            echo "Failed to download from url '$1'!"
        fi
    fi

    return 1
}

if [ -z "$1" ] || [ "$1" = "run" ]; then
    if [ "$AUTOUPDATE" = true ]; then
        BASENAME="$(basename "$SCRIPT_PATH")"

        TARGET_BASENAME="$(grep -E '^#(\s+)?jacklul-asuswrt-scripts-update=' "$SCRIPT_PATH" | sed 's/.*jacklul-asuswrt-scripts-update=//')"
        [ -n "$TARGET_BASENAME" ] && BASENAME=$TARGET_BASENAME

        if download_and_check "$DOWNLOAD_URL/$BASENAME" "$SCRIPT_PATH"; then
            { sleep 1 && cat "/tmp/$SCRIPT_NAME-download" > "$SCRIPT_PATH"; } &
            echo "Script has been updated, please re-run!"
            exit 0
        fi
    fi

    trap 'rm -f "/tmp/$SCRIPT_NAME-download"; exit $?' EXIT

    for ENTRY in "$SCRIPT_DIR"/*.sh; do
        ENTRY="$(readlink -f "$ENTRY")"
        BASENAME="$(basename "$ENTRY")"

        [ "$ENTRY" = "$SCRIPT_PATH" ] && continue
        ! grep -q "jacklul-asuswrt-scripts-update" "$ENTRY" && continue

        TARGET_BASENAME="$(grep -E '^#(\s+)?jacklul-asuswrt-scripts-update=' "$ENTRY" | sed 's/.*jacklul-asuswrt-scripts-update=//')"
        [ -n "$TARGET_BASENAME" ] && BASENAME=$TARGET_BASENAME

        if [ -n "$TARGET_BASENAME" ]; then
            echo "Processing '$ENTRY' ('$BASENAME')..."
        else
            echo "Processing '$ENTRY'..."
        fi

        if download_and_check "$DOWNLOAD_URL/$BASENAME" "$ENTRY"; then
            cat "/tmp/$SCRIPT_NAME-download" > "$ENTRY"
            echo "Updated '$ENTRY'!"
        fi
    done
fi
