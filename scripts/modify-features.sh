#!/bin/sh
# Made by Jack'lul <jacklul.github.io>
#
# Modify rc_support nvram variable
#
# This does not unlock any features, mostly useful to hide stuff from the WebUI
#

#jacklul-asuswrt-scripts-update=modify-features.sh
#shellcheck disable=SC2155

readonly script_path="$(readlink -f "$0")"
readonly script_name="$(basename "$script_path" .sh)"
readonly script_dir="$(dirname "$script_path")"
readonly script_config="$script_dir/$script_name.conf"

FEATURES_REMOVE="" # features to remove from the list
FEATURES_ADD="" # features to add to the list
RUN_EVERY_MINUTE= # verify that the features list is still modified (true/false), empty means false when service-event.sh is available but otherwise true

umask 022 # set default umask

if [ -f "$script_config" ]; then
    #shellcheck disable=SC1090
    . "$script_config"
fi

if [ -z "$RUN_EVERY_MINUTE" ]; then
    [ ! -x "$script_dir/service-event.sh" ] && RUN_EVERY_MINUTE=true
fi

rc_support() {
    case "$1" in
        "modify")
            if [ ! -f /tmp/rc_support.bak ]; then
                rc_support="$(nvram get rc_support)"
                echo "$rc_support" > /tmp/rc_support.bak
            else
                rc_support="$(cat /tmp/rc_support.bak)"
            fi

            if [ -f /tmp/rc_support.last ]; then
                rc_support_last="$(cat /tmp/rc_support.last)"
            fi

            [ "$(nvram get rc_support)" = "$rc_support_last" ] && exit

            for feature_to_remove in $FEATURES_REMOVE; do
                if echo "$rc_support" | grep -Fq "$feature_to_remove"; then
                    rc_support="$(echo "$rc_support" | sed "s/$feature_to_remove//g")"
                fi
            done

            for feature_to_add in $FEATURES_ADD; do
                if ! echo "$rc_support" | grep -Fq "$feature_to_add"; then
                    rc_support="$rc_support $feature_to_add"
                fi
            done

            rc_support="$(echo "$rc_support" | tr -s ' ')"

            echo "$rc_support" > /tmp/rc_support.last

            nvram set rc_support="$rc_support"

            logger -st "$script_name" "Modified rc_support"
        ;;
        "restore")
            rm -f /tmp/rc_support.last

            if [ -f /tmp/rc_support.bak ]; then
                rc_support="$(cat /tmp/rc_support.bak)"

                nvram set rc_support="$rc_support"

                logger -st "$script_name" "Restored original rc_support"
            else
                logger -st "$script_name" "Could not find /tmp/rc_support.bak - cannot restore original rc_support!"
            fi
        ;;
    esac
}

case "$1" in
    "run")
        [ -z "$FEATURES_REMOVE" ] && [ -z "$FEATURES_ADD" ] && exit

        rc_support modify
    ;;
    "start")
        { [ -z "$FEATURES_REMOVE" ] || [ -z "$FEATURES_ADD" ] ; } && { logger -st "$script_name" "Error: Unable to start - configuration is not set"; exit 1; }

        if [ "$RUN_EVERY_MINUTE" = true ]; then
            if [ -x "$script_dir/cron-queue.sh" ]; then
                sh "$script_dir/cron-queue.sh" add "$script_name" "$script_path run"
            else
                cru a "$script_name" "*/1 * * * * $script_path run"
            fi
        fi

        rc_support modify
    ;;
    "stop")
        [ -x "$script_dir/cron-queue.sh" ] && sh "$script_dir/cron-queue.sh" remove "$script_name"
        cru d "$script_name"

        rc_support restore
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
