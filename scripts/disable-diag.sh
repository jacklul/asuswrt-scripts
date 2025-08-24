#!/bin/sh
# Made by Jack'lul <jacklul.github.io>
#
# Disable diagnostics process (?)
#
# Prevents conn_diag from starting amas_portstatus
#

#jacklul-asuswrt-scripts-update=disable-diag.sh
#shellcheck disable=SC2155

readonly script_path="$(readlink -f "$0")"
readonly script_name="$(basename "$script_path" .sh)"
readonly script_dir="$(dirname "$script_path")"
readonly script_config="$script_dir/$script_name.conf"

RUN_EVERY_MINUTE=false # verify that the nvram value is set periodically (true/false)

if [ -f "$script_config" ]; then
    #shellcheck disable=SC1090
    . "$script_config"
fi

case "$1" in
    "run")
        if [ "$(nvram get enable_diag)" != "0" ]; then
            [ ! -f "/tmp/conndiag_default" ] && nvram get enable_diag > "/tmp/conndiag_default"

            nvram set enable_diag=0
            killall conn_diag amas_portstatus

            logger -st "$script_name" "Disabled diagnostics process"
        fi
    ;;
    "start")
        if [ "$RUN_EVERY_MINUTE" = true ]; then
            if [ -x "$script_dir/cron-queue.sh" ]; then
                sh "$script_dir/cron-queue.sh" add "$script_name" "$script_path run"
            else
                cru a "$script_name" "*/1 * * * * $script_path run"
            fi
        fi

        sh "$script_path" run
    ;;
    "stop")
        [ -x "$script_dir/cron-queue.sh" ] && sh "$script_dir/cron-queue.sh" remove "$script_name"
        cru d "$script_name"

        [ -f "/tmp/conndiag_default" ] && nvram set enable_diag="$(cat "/tmp/conndiag_default")"
    ;;
    "restart")
        sh "$script_path" stop
        sh "$script_path" start
    ;;
    *)
        echo "Usage: $0 run|start|stop|restart"
        exit 1
    ;;
esac
