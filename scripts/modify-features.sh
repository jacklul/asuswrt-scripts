#!/bin/sh
# Made by Jack'lul <jacklul.github.io>
#
# Modify rc_support nvram variable
#
# This does not unlock any features, mostly useful to hide stuff from the WebUI
#

#jas-update=modify-features.sh
#shellcheck disable=SC2155
#shellcheck source=./common.sh
readonly common_script="$(dirname "$0")/common.sh"
if [ -f "$common_script" ]; then . "$common_script"; else { echo "$common_script not found"; exit 1; } fi

FEATURES_REMOVE="" # features to remove from the list
FEATURES_ADD="" # features to add to the list
CACHE_FILE="$TMP_DIR/$script_name" # file to store last contents of the variable in
BACKUP_FILE="/tmp/rc_support.bak" # file to store backup of the variable in
RUN_EVERY_MINUTE= # verify that the features list is still modified (true/false), empty means false when service-event script is available but otherwise true

load_script_config

rc_support() {
    case "$1" in
        "modify")
            if [ ! -f "$BACKUP_FILE" ]; then
                rc_support="$(nvram get rc_support)"
                echo "$rc_support" > "$BACKUP_FILE"
                chmod 644 "$BACKUP_FILE"
            else
                rc_support="$(cat "$BACKUP_FILE")"
            fi

            if [ -f "$CACHE_FILE" ]; then
                rc_support_last="$(cat "$CACHE_FILE")"
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

            echo "$rc_support" > "$CACHE_FILE"

            nvram set rc_support="$rc_support"

            logger -st "$script_name" "Modified rc_support"
        ;;
        "restore")
            rm -f "$CACHE_FILE"

            if [ -f "$BACKUP_FILE" ]; then
                rc_support="$(cat "$BACKUP_FILE")"

                nvram set rc_support="$rc_support"

                logger -st "$script_name" "Restored original rc_support"
            else
                logger -st "$script_name" "Could not find '$BACKUP_FILE' - cannot restore original rc_support!"
            fi
        ;;
    esac
}

case "$1" in
    "run")
        [ -z "$FEATURES_REMOVE" ] && [ -z "$FEATURES_ADD" ] && exit
        rc_support modify
    ;;
    "check") # used by service-event script
        if [ -f "$CACHE_FILE" ]; then
            rc_support_last="$(cat "$CACHE_FILE")"

            [ "$(nvram get rc_support)" = "$rc_support_last" ] && exit 0
        fi

        exit 1
    ;;
    "start")
        { [ -z "$FEATURES_REMOVE" ] || [ -z "$FEATURES_ADD" ] ; } && { logger -st "$script_name" "Unable to start - configuration is not set"; exit 1; }

        rc_support modify

        # Set value of empty RUN_EVERY_MINUTE depending on situation
        execute_script_basename "service-event.sh" check && service_event_active=true
        [ -z "$RUN_EVERY_MINUTE" ] && [ -z "$service_event_active" ] && RUN_EVERY_MINUTE=true

        if [ "$RUN_EVERY_MINUTE" = true ]; then
            crontab_entry add "*/1 * * * * $script_path run"
        fi
    ;;
    "stop")
        crontab_entry delete
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
