#!/bin/sh
# Made by Jack'lul <jacklul.github.io>
#
# Handle hotplug events
#

#jacklul-asuswrt-scripts-update=hotplug-event.sh
#shellcheck disable=SC2155

readonly script_path="$(readlink -f "$0")"
readonly script_name="$(basename "$script_path" .sh)"
readonly script_dir="$(dirname "$script_path")"
readonly script_config="$script_dir/$script_name.conf"

EXECUTE_COMMAND="" # command to execute in addition to build-in script (receives arguments: $1 = subsystem, $2 = action)
RUN_EVERY_MINUTE=false # verify that the hotplug configuration is modified (true/false), this usually should not be needed

umask 022 # set default umask

if [ -f "$script_config" ]; then
    #shellcheck disable=SC1090
    . "$script_config"
fi

lockfile() { #LOCKFILE_START#
    [ -z "$script_name" ] && script_name="$(basename "$0" .sh)"

    _lockfile="/var/lock/script-$script_name.lock"
    _pidfile="/var/run/script-$script_name.pid"
    _fd=100
    _fd_max=200

    if [ -n "$2" ]; then
        _lockfile="/var/lock/script-$script_name-$2.lock"
        _pidfile="/var/run/script-$script_name-$2.lock"
    fi

    [ -n "$3" ] && [ "$3" -eq "$3" ] && _fd="$3" && _fd_max="$3"
    [ -n "$4" ] && [ "$4" -eq "$4" ] && _fd_max="$4"

    [ ! -d /var/lock ] && { mkdir -p /var/lock || exit 1; }
    [ ! -d /var/run ] && { mkdir -p /var/run || exit 1; }

    _lockpid=
    [ -f "$_pidfile" ] && _lockpid="$(cat "$_pidfile")"

    case "$1" in
        "lockwait"|"lockfail"|"lockexit")
            while [ -f "/proc/$$/fd/$_fd" ]; do
                _fd=$((_fd+1))
                [ "$_fd" -gt "$_fd_max" ] && { logger -st "$script_name" "No free file descriptors available"; exit 1; }
            done

            eval exec "$_fd>$_lockfile"

            case "$1" in
                "lockwait")
                    _lockwait=0
                    while ! flock -nx "$_fd"; do # flock -x "$_fd" sometimes gets stuck
                        sleep 1
                        if [ "$_lockwait" -ge 60 ]; then
                            logger -st "$script_name" "Failed to acquire a lock after 60 seconds"
                            exit 1
                        fi
                    done
                ;;
                "lockfail")
                    flock -nx "$_fd" || return 1
                ;;
                "lockexit")
                    flock -nx "$_fd" || exit 1
                ;;
            esac

            echo $$ > "$_pidfile"
            chmod 644 "$_pidfile"
            trap 'flock -u $_fd; rm -f "$_lockfile" "$_pidfile"; exit $?' INT TERM EXIT
        ;;
        "unlock")
            flock -u "$_fd"
            eval exec "$_fd>&-"
            rm -f "$_lockfile" "$_pidfile"
            trap - INT TERM EXIT
        ;;
        "check")
            [ -n "$_lockpid" ] && [ -f "/proc/$_lockpid/stat" ] && return 0
            return 1
        ;;
        "kill")
            [ -n "$_lockpid" ] && [ -f "/proc/$_lockpid/stat" ] && kill -9 "$_lockpid" && return 0
            return 1
        ;;
    esac
} #LOCKFILE_END#

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

                logger -st "$script_name" "Modified hotplug configuration"
            fi
        ;;
        "restore")
            if [ -f /etc/hotplug2.rules ] && [ -f /etc/hotplug2.rules.bak ]; then
                rm /etc/hotplug2.rules
                cp /etc/hotplug2.rules.bak /etc/hotplug2.rules

                killall hotplug2 2> /dev/null

                logger -st "$script_name" "Restored original hotplug configuration"
            fi
        ;;
    esac

    lockfile unlock
}

case "$1" in
    "run")
        if ! grep -Fq "$script_path" /etc/hotplug2.rules; then
            hotplug_config modify
        fi
    ;;
    "event")
        lockfile lockwait event "$2"

        case "$2" in
            "block"|"net"|"misc")
                logger -st "$script_name" "Running script (args: '$2' '$3')"
            ;;
        esac

        # $2 = subsystem, $3 = action
        case "$2" in
            "block")
                [ -x "$script_dir/usb-mount.sh" ] && sh "$script_dir/usb-mount.sh" hotplug
                [ -x "$script_dir/swap.sh" ] && sh "$script_dir/swap.sh" hotplug
                [ -x "$script_dir/entware.sh" ] && sh "$script_dir/entware.sh" hotplug
            ;;
            "net")
                [ -x "$script_dir/usb-network.sh" ] && sh "$script_dir/usb-network.sh" hotplug
            ;;
            "misc")
                # empty for now
            ;;
        esac

        [ -n "$EXECUTE_COMMAND" ] && $EXECUTE_COMMAND "$2" "$3"

        lockfile unlock event "$2"
        exit
    ;;
    "start")
        if [ "$RUN_EVERY_MINUTE" = true ]; then
            if [ -x "$script_dir/cron-queue.sh" ]; then
                sh "$script_dir/cron-queue.sh" add "$script_name" "$script_path run"
            else
                cru a "$script_name" "*/1 * * * * $script_path run"
            fi
        fi

        hotplug_config modify
    ;;
    "stop")
        [ -x "$script_dir/cron-queue.sh" ] && sh "$script_dir/cron-queue.sh" remove "$script_name"
        cru d "$script_name"

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
