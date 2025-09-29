#!/bin/sh
# Made by Jack'lul <jacklul.github.io>
#
# Handle hotplug events
#

#jas-update=hotplug-event.sh
#shellcheck disable=SC2155
#shellcheck source=./common.sh
readonly common_script="$(dirname "$0")/common.sh"
if [ -f "$common_script" ]; then . "$common_script"; else { echo "$common_script not found" >&2; exit 1; } fi

EXECUTE_COMMAND="" # command to execute in addition to build-in script (receives arguments: $1 = subsystem, $2 = action)
NO_INTEGRATION=false # set to true to disable integration with jacklul/asuswrt-scripts
RUN_EVERY_MINUTE=false # verify that the hotplug configuration is still modified (true/false), this is usually not be needed

load_script_config

hotplug_config() {
    lockfile lockwait

    case "$1" in
        "modify")
            if [ -f /etc/hotplug2.rules ]; then
                grep -Fq "$script_path" /etc/hotplug2.rules && return # already modified

                [ ! -f /etc/hotplug2.rules.bak ] && mv /etc/hotplug2.rules /etc/hotplug2.rules.bak

                cat /etc/hotplug2.rules.bak > /etc/hotplug2.rules

                cat <<EOT >> /etc/hotplug2.rules

# Added by $script_name
SUBSYSTEM == block, DEVICENAME is set, ACTION ~~ ^(add|remove)$ {
    exec "$script_path" event %SUBSYSTEM% %ACTION% ;
}
SUBSYSTEM == net, DEVICENAME is set, ACTION ~~ ^(add|remove)$ {
    exec "$script_path" event %SUBSYSTEM% %ACTION% ;
}
SUBSYSTEM == misc, DEVICENAME ~~ ^(tun|tap)$, ACTION ~~ ^(add|remove)$ {
    exec "$script_path" event %SUBSYSTEM% %ACTION% ;
}
EOT

                killall hotplug2 2> /dev/null

                logecho "Modified hotplug configuration" alert
            fi
        ;;
        "restore")
            if [ -f /etc/hotplug2.rules ] && [ -f /etc/hotplug2.rules.bak ]; then
                rm /etc/hotplug2.rules
                cp /etc/hotplug2.rules.bak /etc/hotplug2.rules

                killall hotplug2 2> /dev/null

                logecho "Restored original hotplug configuration" alert
            fi
        ;;
    esac

    lockfile unlock
}

case "$1" in
    "run")
        if [ -f /etc/hotplug2.rules ] && ! grep -Fq "$script_path" /etc/hotplug2.rules; then
            hotplug_config modify
        fi
    ;;
    "event")
        lockfile lockwait "event_${2}_${3}"

        case "$2" in
            "block"|"net"|"misc")
                logecho "Running script (args: '$2' '$3')"
            ;;
        esac

        if [ "$NO_INTEGRATION" != true ]; then
            # $2 = subsystem, $3 = action
            case "$2" in
                "block")
                    execute_script_basename "fstrim.sh" hotplug
                    execute_script_basename "swap.sh" hotplug
                    execute_script_basename "entware.sh" hotplug
                ;;
                "net")
                    execute_script_basename "usb-network.sh" hotplug
                ;;
                "misc")
                    # empty for now
                ;;
            esac
        fi

        [ -n "$EXECUTE_COMMAND" ] && $EXECUTE_COMMAND "$2" "$3"

        lockfile unlock "event_${2}_${3}"
        exit
    ;;
    "start")
        hotplug_config modify

        if [ "$RUN_EVERY_MINUTE" = true ]; then
            crontab_entry add "*/1 * * * * $script_path run"
        fi
    ;;
    "stop")
        crontab_entry delete
        hotplug_config restore
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
