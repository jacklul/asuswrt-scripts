#!/bin/sh
# Made by Jack'lul <jacklul.github.io>
#
# Download files from netboot.xyz to specified directory
#
# Based on:
#  https://github.com/RMerl/asuswrt-merlin.ng/wiki/Enable-PXE-booting-into-netboot.xyz
#

# jacklul-asuswrt-scripts-update
#shellcheck disable=SC2155

readonly SCRIPT_PATH="$(readlink -f "$0")"
readonly SCRIPT_NAME="$(basename "$SCRIPT_PATH" .sh)"
readonly SCRIPT_DIR="$(dirname "$SCRIPT_PATH")"
readonly SCRIPT_CONFIG="$SCRIPT_DIR/$SCRIPT_NAME.conf"
readonly SCRIPT_TAG="$(basename "$SCRIPT_PATH")"

FILES="netboot.xyz.efi netboot.xyz.kpxe" # what files to download, space separated
DIRECTORY="/tmp/netboot.xyz" # where to save the files
BASE_URL="https://boot.netboot.xyz/ipxe/" # base download URL, with ending slash

if [ -f "$SCRIPT_CONFIG" ]; then
    #shellcheck disable=SC1090
    . "$SCRIPT_CONFIG"
fi

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
} #ISSTARTEDBYSYSTEM_END#

case "$1" in
    "run")
        { [ "$(nvram get wan0_state_t)" != "2" ] && [ "$(nvram get wan1_state_t)" != "2" ]; } && { echo "WAN network is not connected"; exit; }
        [ -z "$($CURL_BINARY -fs "https://boot.netboot.xyz")" ] && { echo "Cannot reach boot.netboot.xyz"; exit 1; }

        [ ! -d "$DIRECTORY" ] && mkdir -p "$DIRECTORY"

        DOWNLOADED=""
        FAILED=""
        for FILE in $FILES; do
            [ -f "$DIRECTORY/$FILE" ] && continue

            if $CURL_BINARY -fsSL "$BASE_URL$FILE" -o "$DIRECTORY/$FILE" && [ -f "$DIRECTORY/$FILE" ]; then
                DOWNLOADED="$DOWNLOADED $FILE"
            else
                FAILED="$FAILED $FILE"
            fi
        done

        [ -n "$DOWNLOADED" ] && logger -st "$SCRIPT_TAG" "Downloaded files from netboot.xyz:$DOWNLOADED"
        [ -n "$FAILED" ] && logger -st "$SCRIPT_TAG" "Failed to downloaded files from netboot.xyz:$FAILED"

        [ -z "$FAILED" ] && sh "$SCRIPT_PATH" stop
    ;;
    "start")
        if [ -x "$SCRIPT_DIR/cron-queue.sh" ]; then
            sh "$SCRIPT_DIR/cron-queue.sh" add "$SCRIPT_NAME" "$SCRIPT_PATH run"
        else
            cru a "$SCRIPT_NAME" "*/1 * * * * $SCRIPT_PATH run"
        fi

        if is_started_by_system; then
            {
                sh "$SCRIPT_PATH" run
            } &
        fi
    ;;
    "stop")
        [ -x "$SCRIPT_DIR/cron-queue.sh" ] && sh "$SCRIPT_DIR/cron-queue.sh" remove "$SCRIPT_NAME"
        cru d "$SCRIPT_NAME"
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
