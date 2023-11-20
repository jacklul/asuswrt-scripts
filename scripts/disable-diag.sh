#!/bin/sh
# Made by Jack'lul <jacklul.github.io>
#
# Disable diagnostics (?)
#
# Prevents conn_diag from starting amas_portstatus
#

#shellcheck disable=SC2155,SC2009

readonly SCRIPT_PATH="$(readlink -f "$0")"
readonly SCRIPT_NAME="$(basename "$SCRIPT_PATH" .sh)"

case "$1" in
    "run")
        if [ "$(nvram get enable_diag)" != "0" ]; then
            [ ! -f "/tmp/conndiag_default" ] && nvram get enable_diag > "/tmp/conndiag_default"

            nvram set enable_diag=0
            killall conn_diag amas_portstatus
        fi
    ;;
    "start")
        cru a "$SCRIPT_NAME" "*/1 * * * * $SCRIPT_PATH run"

        sh "$SCRIPT_PATH" run
    ;;
    "stop")
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
