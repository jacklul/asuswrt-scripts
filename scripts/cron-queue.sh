#!/bin/sh
# Made by Jack'lul <jacklul.github.io>
#
# Run "every minute" jobs one after another to decrease performance impact
# This only applies to scripts from jacklul/asuswrt-script repository
#

#jas-update=cron-queue.sh
#shellcheck disable=SC2155
#shellcheck source=./common.sh
readonly common_script="$(dirname "$0")/common.sh"
if [ -f "$common_script" ]; then . "$common_script"; else { echo "$common_script not found"; exit 1; } fi

QUEUE_FILE="$TMP_DIR/$script_name" # where to store the queue

load_script_config

[ -z "$QUEUE_FILE" ] && { echo "Queue file is not set"; exit 1; }

case "$1" in
    "run")
        lockfile lockfail run

        #( sh "$QUEUE_FILE" < /dev/null )
        while IFS= read -r line; do
            line=$(echo "$line" | sed 's/[[:space:]]*#.*$//; s/^[[:space:]]*//; s/[[:space:]]*$//')
            [ -z "$line" ] && continue
            echo "Running: $line"
            #shellcheck disable=SC2086
            ( $line < /dev/null )
        done < "$QUEUE_FILE"

        lockfile unlock run
    ;;
    "add"|"delete"|"a"|"d")
        add="$1"
        [ "$1" = "a" ] && add=add

        [ -z "$2" ] && { echo "Entry ID not set"; exit 1; }
        { [ -z "$3" ] && [ "$add" = "add" ] ; } && { echo "Entry command not set"; exit 1; }

        lockfile lockwait

        [ -f "$QUEUE_FILE" ] && sed "/#$(sed_quote "$2")#$/d" -i "$QUEUE_FILE"
        [ "$add" = "add" ] && echo "$3 #$2#" >> "$QUEUE_FILE"

        lockfile unlock
    ;;
    "list"|"l")
        [ ! -f "$QUEUE_FILE" ] && { echo "Queue file does not exist"; exit 1; }

        cat "$QUEUE_FILE"
    ;;
    "check"|"c")
        [ -z "$2" ] && { echo "Entry ID not provided"; exit 1; }

        if [ -f "$QUEUE_FILE" ]; then
            grep -Fq "#$2#" "$QUEUE_FILE" && exit 0
        fi

        exit 1
    ;;
    "start")
        cru a "jas-$script_name" "*/1 * * * * $script_path run"
    ;;
    "stop")
        cru d "jas-$script_name"
    ;;
    "restart")
        sh "$script_path" stop
        sh "$script_path" start
    ;;
    *)
        echo "Usage: $0 run|start|stop|restart|add|remove|list|check"
        exit 1
    ;;
esac
