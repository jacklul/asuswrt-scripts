#!/bin/sh
# Made by Jack'lul <jacklul.github.io>
#
# Runs Tailscale service
#
# Note that automatic download of Tailscale binaries stores them in /tmp directory - make sure you have enough free RAM!
# You will want to start this manually first to login.
#
# Use Entware package instead of this script when possible!
#

#shellcheck disable=SC2155

readonly SCRIPT_PATH="$(readlink -f "$0")"
readonly SCRIPT_NAME="$(basename "$SCRIPT_PATH" .sh)"
readonly SCRIPT_DIR="$(dirname "$SCRIPT_PATH")"
readonly SCRIPT_CONFIG="$SCRIPT_DIR/$SCRIPT_NAME.conf"
readonly SCRIPT_TAG="$(basename "$SCRIPT_PATH")"

#shellcheck disable=SC2034
readonly SCRIPT_ARCHIVED=true

STATE_FILE="/jffs/tailscaled.state" # where to store state file, preferably persistent between reboots
INTERFACE="tailscale0" # interface to use, if you change TAILSCALED_ARGUMENTS make sure correct interface is being used
TAILSCALED_ARGUMENTS="-no-logs-no-support -tun $INTERFACE" # 'tailscaled' arguments
TAILSCALE_ARGUMENTS="--accept-dns=false --advertise-exit-node" # 'tailscale up' arguments, refer to https://tailscale.com/kb/1080/cli/#command-reference
TAILSCALED_PATH="" # path to tailscaled binary, fill TAILSCALE_DOWNLOAD_URL to automatically download
TAILSCALE_PATH="" # path to tailscale binary, fill TAILSCALE_DOWNLOAD_URL to automatically download
TAILSCALE_DOWNLOAD_URL="" # Tailscale tgz download URL, "https://pkgs.tailscale.com/stable/tailscale_latest_arm.tgz" should work

if [ -f "$SCRIPT_CONFIG" ]; then
    #shellcheck disable=SC1090
    . "$SCRIPT_CONFIG"
fi

CHAIN="TAILSCALE"
FOR_IPTABLES="iptables"

[ "$(nvram get ipv6_service)" != "disabled" ] && FOR_IPTABLES="$FOR_IPTABLES ip6tables"

lockfile() { #LOCKFUNC_START#
    _LOCKFILE="/tmp/$SCRIPT_NAME.lock"

    case "$1" in
        "lock")
            if [ -f "$_LOCKFILE" ]; then
                _LOCKWAITLIMIT=60
                _LOCKWAITTIMER=0
                while [ "$_LOCKWAITTIMER" -lt "$_LOCKWAITLIMIT" ]; do
                    [ ! -f "$_LOCKFILE" ] && break

                    _LOCKPID="$(sed -n '1p' "$_LOCKFILE")"
                    _LOCKCMD="$(sed -n '2p' "$_LOCKFILE")"

                    [ ! -d "/proc/$_LOCKPID" ] && break;
                    [ "$_LOCKPID" = "$$" ] && break;

                    _LOCKWAITTIMER=$((_LOCKWAITTIMER+1))
                    sleep 1
                done

                [ "$_LOCKWAITTIMER" -ge "$_LOCKWAITLIMIT" ] && { logger -st "$SCRIPT_TAG" "Unable to obtain lock after $_LOCKWAITLIMIT seconds, held by $_LOCKPID ($_LOCKCMD)"; exit 1; }
            fi

            echo "$$" > "$_LOCKFILE"
            echo "$@" >> "$_LOCKFILE"
            trap 'rm -f "$_LOCKFILE"; exit $?' EXIT
        ;;
        "unlock")
            if [ -f "$_LOCKFILE" ]; then
                _LOCKPID="$(sed -n '1p' "$_LOCKFILE")"

                if [ -d "/proc/$_LOCKPID" ] && [ "$_LOCKPID" != "$$" ]; then
                    echo "Attempted to remove not own lock"
                    exit 1
                fi

                rm -f "$_LOCKFILE"
            fi
            
            trap - EXIT
        ;;
    esac
} #LOCKFUNC_END#

download_tailscale() {
    if [ -n "$TAILSCALE_DOWNLOAD_URL" ]; then
        logger -st "$SCRIPT_TAG" "Downloading Tailscale binaries from '$TAILSCALE_DOWNLOAD_URL'..."

        set -e
        mkdir -p /tmp/download
        cd /tmp/download
        curl -fsSL "$TAILSCALE_DOWNLOAD_URL" -o "tailscale.tgz"
        tar zxf "tailscale.tgz"
        mv ./*/tailscaled /tmp/tailscaled
        mv ./*/tailscale /tmp/tailscale
        rm -fr /tmp/download/*
        chmod +x /tmp/tailscaled /tmp/tailscale
        set +e

        TAILSCALED_PATH="/tmp/tailscaled"
        TAILSCALE_PATH="/tmp/tailscale"
    fi
}

firewall_rules() {
    [ -z "$INTERFACE" ] && { logger -st "$SCRIPT_TAG" "Tailscale interface is not set"; exit 1; }

    lockfile lock

    _RULES_ADDED=0

    for _IPTABLES in $FOR_IPTABLES; do
        case "$1" in
            "add")
                if ! $_IPTABLES -nL "$CHAIN" >/dev/null 2>&1; then
                    _RULES_ADDED=1

                    _INPUT_END="$($_IPTABLES -nL INPUT --line-numbers | sed '/^num\|^$\|^Chain/d' | wc -l)"

                    $_IPTABLES -N "$CHAIN"
                    $_IPTABLES -I INPUT "$_INPUT_END" -i "$INTERFACE" -j "$CHAIN"
                    $_IPTABLES -A $CHAIN -j "ACCEPT"
                fi
            ;;
            "remove")
                if $_IPTABLES -nL "$CHAIN" >/dev/null 2>&1; then
                    $_IPTABLES -D INPUT -i "$INTERFACE" -j "$CHAIN"
                    $_IPTABLES -F "$CHAIN"
                    $_IPTABLES -X "$CHAIN"
                fi
            ;;
        esac
    done

    [ "$_RULES_ADDED" = 1 ] && logger -st "$SCRIPT_TAG" "Added firewall rules for Tailscale interface ($INTERFACE)"

    lockfile unlock
}

#shellcheck disable=SC2009
TAILSCALED_PID="$(ps w | grep "tailscaled" | grep -v grep | awk '{print $1}' | tr '\n' ' ' | awk '{$1=$1};1')"

case "$1" in
    "run")
        [ ! -f "$TAILSCALED_PATH" ] && [ -f "/tmp/tailscaled" ] && TAILSCALED_PATH="/tmp/tailscaled"
        [ ! -f "$TAILSCALE_PATH" ] && [ -f "/tmp/tailscale" ] && TAILSCALE_PATH="/tmp/tailscale"

        if [ ! -f "$TAILSCALED_PATH" ] || [ ! -f "$TAILSCALE_PATH" ]; then
            download_tailscale

            [ ! -f "$TAILSCALED_PATH" ] && { logger -st "$SCRIPT_TAG" "Could not find tailscaled binary: $TAILSCALED_PATH"; exit 1; }
            [ ! -f "$TAILSCALE_PATH" ] && { logger -st "$SCRIPT_TAG" "Could not find tailscale binary: $TAILSCALE_PATH"; exit 1; }
        fi

        if [ -f "/opt/bin/tailscaled" ]; then
            logger -st "$SCRIPT_TAG" "Tailscale was installed through Entware - do not use this script in this case"
            cru d "$SCRIPT_NAME"
            exit 1
        fi

        if [ -z "$TAILSCALED_PID" ]; then
            logger -st "$SCRIPT_TAG" "Starting Tailscale daemon..."

            ! lsmod | grep -q tun && modprobe tun && sleep 1

            #shellcheck disable=SC2086
            "$TAILSCALED_PATH" --state="$STATE_FILE" $TAILSCALED_ARGUMENTS >/dev/null 2>&1 &
            sleep 5
        fi

        #shellcheck disable=SC2086
        "$TAILSCALE_PATH" up $TAILSCALE_ARGUMENTS

        sh "$SCRIPT_PATH" firewall
    ;;
    "init-run")
        if [ -z "$TAILSCALED_PID" ]; then
            nohup "$SCRIPT_PATH" run >/dev/null 2>&1 &
        else
            sh "$SCRIPT_PATH" firewall
        fi
    ;;
    "firewall")
        if [ -n "$TAILSCALED_PID" ]; then
            firewall_rules add
        else
            firewall_rules remove
        fi
    ;;
    "start")
        cru a "$SCRIPT_NAME" "*/1 * * * * $SCRIPT_PATH init-run"
    ;;
    "stop")
        cru d "$SCRIPT_NAME"

        firewall_rules remove

        [ -n "$TAILSCALED_PID" ] && kill "$TAILSCALED_PID"
    ;;
    "restart")
        sh "$SCRIPT_PATH" stop
        sh "$SCRIPT_PATH" start
    ;;
    *)
        echo "Usage: $0 run|start|stop|restart|firewall"
        exit 1
    ;;
esac
