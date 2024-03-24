#!/bin/sh
# Made by Jack'lul <jacklul.github.io>
#
# Disable diagnostics (?)
#
# Prevents conn_diag from starting amas_portstatus
#

# jacklul-asuswrt-scripts-update
#shellcheck disable=SC2155,SC2009

readonly SCRIPT_PATH="$(readlink -f "$0")"
readonly SCRIPT_NAME="$(basename "$SCRIPT_PATH" .sh)"
readonly SCRIPT_DIR="$(dirname "$SCRIPT_PATH")"

case "$1" in
    "run")
        if [ "$(nvram get enable_diag)" != "0" ]; then
            [ ! -f "/tmp/conndiag_default" ] && nvram get enable_diag > "/tmp/conndiag_default"

            nvram set enable_diag=0
            killall conn_diag amas_portstatus
        fi
    ;;
    "start")
        if [ -x "$SCRIPT_DIR/cron-queue.sh" ]; then
            sh "$SCRIPT_DIR/cron-queue.sh" add "$SCRIPT_NAME" "$SCRIPT_PATH run"
        else
            cru a "$SCRIPT_NAME" "*/1 * * * * $SCRIPT_PATH run"
        fi

        sh "$SCRIPT_PATH" run
    ;;
    "stop")
        [ -x "$SCRIPT_DIR/cron-queue.sh" ] && sh "$SCRIPT_DIR/cron-queue.sh" remove "$SCRIPT_NAME"
        cru d "$SCRIPT_NAME"

        [ -f "/tmp/conndiag_default" ] && nvram set enable_diag="$(cat "/tmp/conndiag_default")"
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
