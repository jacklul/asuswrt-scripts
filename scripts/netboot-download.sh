#!/bin/sh
# Made by Jack'lul <jacklul.github.io>
#
# Download files from netboot.xyz to specified directory
#
# Based on:
#  https://github.com/RMerl/asuswrt-merlin.ng/wiki/Enable-PXE-booting-into-netboot.xyz
#

#jacklul-asuswrt-scripts-update=netboot-download.sh
#shellcheck disable=SC2155

readonly SCRIPT_PATH="$(readlink -f "$0")"
readonly SCRIPT_NAME="$(basename "$SCRIPT_PATH" .sh)"
readonly SCRIPT_DIR="$(dirname "$SCRIPT_PATH")"
readonly SCRIPT_CONFIG="$SCRIPT_DIR/$SCRIPT_NAME.conf"
readonly SCRIPT_TAG="$(basename "$SCRIPT_PATH")"

FILES="netboot.xyz.efi netboot.xyz.kpxe" # what files to download, space separated
DIRECTORY="/tmp/netboot.xyz" # where to save the files
BASE_URL="https://boot.netboot.xyz/ipxe" # base download URL, without ending slash

if [ -f "$SCRIPT_CONFIG" ]; then
    #shellcheck disable=SC1090
    . "$SCRIPT_CONFIG"
fi

CURL_BINARY="curl"
[ -f /opt/bin/curl ] && CURL_BINARY="/opt/bin/curl" # prefer Entware's curl as it is not modified by Asus


lockfile() { #LOCKFILE_START#
    _LOCKFILE="/var/lock/script-$SCRIPT_NAME.lock"
    _PIDFILE="/var/run/script-$SCRIPT_NAME.pid"
    _FD=100
    _FD_MAX=200

    if [ -n "$2" ]; then
        _LOCKFILE="/var/lock/script-$SCRIPT_NAME-$2.lock"
        _PIDFILE="/var/run/script-$SCRIPT_NAME-$2.lock"
    fi

    [ -n "$3" ] && [ "$3" -eq "$3" ] && _FD="$3" && _FD_MAX="$3"
    [ -n "$4" ] && [ "$4" -eq "$4" ] && _FD_MAX="$4"

    [ ! -d /var/lock ] && mkdir -p /var/lock
    [ ! -d /var/run ] && mkdir -p /var/run

    _LOCKPID=
    [ -f "$_PIDFILE" ] && _LOCKPID="$(cat "$_PIDFILE")"

    case "$1" in
        "lockwait"|"lockfail"|"lockexit")
            while [ -f "/proc/$$/fd/$_FD" ]; do
                #echo "File descriptor $_FD is already in use ($(readlink -f "/proc/$$/fd/$_FD"))"
                _FD=$((_FD+1))

                [ "$_FD" -gt "$_FD_MAX" ] && { echo "Failed to find available file descriptor"; exit 1; }
            done

            eval exec "$_FD>$_LOCKFILE"

            case "$1" in
                "lockwait")
                    _LOCK_WAITED=0
                    while ! flock -nx "$_FD"; do #flock -x "$_FD"
                        sleep 1
                        if [ "$_LOCK_WAITED" -ge 60 ]; then
                            echo "Failed to acquire a lock after 60 seconds"
                            exit 1
                        fi
                    done
                ;;
                "lockfail")
                    flock -nx "$_FD" || return 1
                ;;
                "lockexit")
                    flock -nx "$_FD" || exit 1
                ;;
            esac

            echo $$ > "$_PIDFILE"
            trap 'flock -u $_FD; rm -f "$_LOCKFILE" "$_PIDFILE"; exit $?' INT TERM EXIT
        ;;
        "unlock")
            flock -u "$_FD"
            rm -f "$_LOCKFILE" "$_PIDFILE"
            trap - INT TERM EXIT
        ;;
        "check")
            [ -n "$_LOCKPID" ] && [ -f "/proc/$_LOCKPID/stat" ] && return 0
            return 1
        ;;
        "kill")
            [ -n "$_LOCKPID" ] && [ -f "/proc/$_LOCKPID/stat" ] && kill -9 "$_LOCKPID" && return 0
            return 1
        ;;
    esac
} #LOCKFILE_END#

is_started_by_system() { #ISSTARTEDBYSYSTEM_START#
    _PPID=$PPID
    while true; do
        [ -z "$_PPID" ] && break
        _PPID=$(< "/proc/$_PPID/stat" awk '{print $4}')

        grep -q "cron" "/proc/$_PPID/comm" && return 0
        grep -q "hotplug" "/proc/$_PPID/comm" && return 0
        [ "$_PPID" -gt 1 ] || break
    done

    return 1
} #ISSTARTEDBYSYSTEM_END#

case "$1" in
    "run")
        lockfile lockfail || { echo "Already running! ($_LOCKPID)"; exit 1; }

        { [ "$(nvram get wan0_state_t)" != "2" ] && [ "$(nvram get wan1_state_t)" != "2" ] ; } && { echo "WAN network is not connected"; exit 1; }
        [ -z "$($CURL_BINARY -fs "https://boot.netboot.xyz")" ] && { echo "Cannot reach boot.netboot.xyz"; exit 1; }

        #logger -st "$SCRIPT_TAG" "Downloading files from netboot.xyz..."

        [ ! -d "$DIRECTORY" ] && mkdir -p "$DIRECTORY"

        DOWNLOADED=""
        FAILED=""
        for FILE in $FILES; do
            [ -f "$DIRECTORY/$FILE" ] && continue

            if $CURL_BINARY -fsSL "$BASE_URL/$FILE" -o "$DIRECTORY/$FILE" && [ -f "$DIRECTORY/$FILE" ]; then
                DOWNLOADED="$DOWNLOADED $FILE"
            else
                FAILED="$FAILED $FILE"
            fi
        done

        [ -n "$DOWNLOADED" ] && logger -st "$SCRIPT_TAG" "Downloaded files from netboot.xyz:$DOWNLOADED"
        #[ -n "$FAILED" ] && logger -st "$SCRIPT_TAG" "Failed to downloaded files from netboot.xyz:$FAILED"
        [ -z "$FAILED" ] && sh "$SCRIPT_PATH" stop

        lockfile unlock
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
        else
            sh "$SCRIPT_PATH" run
        fi
    ;;
    "stop")
        [ -x "$SCRIPT_DIR/cron-queue.sh" ] && sh "$SCRIPT_DIR/cron-queue.sh" remove "$SCRIPT_NAME"
        cru d "$SCRIPT_NAME"

        lockfile kill
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
