#!/bin/sh
# Made by Jack'lul <jacklul.github.io>
#
# Handle hotplug events
#

# jacklul-asuswrt-scripts-update
#shellcheck disable=SC2155

readonly SCRIPT_PATH="$(readlink -f "$0")"
readonly SCRIPT_NAME="$(basename "$SCRIPT_PATH" .sh)"
readonly SCRIPT_DIR="$(dirname "$SCRIPT_PATH")"
readonly SCRIPT_CONFIG="$SCRIPT_DIR/$SCRIPT_NAME.conf"
readonly SCRIPT_TAG="$(basename "$SCRIPT_PATH")"

EXECUTE_COMMAND="" # command to execute in addition to build-in script (receives arguments: $1 = subsystem, $2 = action)

if [ -f "$SCRIPT_CONFIG" ]; then
    #shellcheck disable=SC1090
    . "$SCRIPT_CONFIG"
fi

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
                echo "File descriptor $_FD is already in use ($(readlink -f "/proc/$$/fd/$_FD"))"
                _FD=$((_FD+1))

                [ "$_FD" -gt "$_FD_MAX" ] && exit 1
            done

            eval exec "$_FD>$_LOCKFILE"

            case "$1" in
                "lockwait")
                    flock -x "$_FD"
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

hotplug_config() {
    case "$1" in
        "modify")
            if [ -f /etc/hotplug2.rules ]; then
                grep -q "$SCRIPT_PATH" /etc/hotplug2.rules && return # already modified

                [ ! -f /etc/hotplug2.rules.bak ] && mv /etc/hotplug2.rules /etc/hotplug2.rules.bak

                cat /etc/hotplug2.rules.bak > /etc/hotplug2.rules

                cat <<EOT >> /etc/hotplug2.rules
SUBSYSTEM == block, DEVICENAME is set, ACTION ~~ ^(add|remove)$ {
    exec $SCRIPT_DIR/hotplug-event.sh run %SUBSYSTEM% %ACTION% ;
}
SUBSYSTEM == net, DEVICENAME is set, ACTION ~~ ^(add|remove)$ {
    exec $SCRIPT_DIR/hotplug-event.sh run %SUBSYSTEM% %ACTION% ;
}
SUBSYSTEM == misc, DEVICENAME ~~ ^(tun|tap)$, ACTION ~~ ^(add|remove)$ {
    exec $SCRIPT_DIR/hotplug-event.sh run %SUBSYSTEM% %ACTION% ;
}
EOT

                killall hotplug2

                logger -st "$SCRIPT_TAG" "Modified hotplug configuration"
            fi
        ;;
        "restore")
            if [ -f /etc/hotplug2.rules ] && [ -f /etc/hotplug2.rules.bak ]; then
                rm /etc/hotplug2.rules
                cp /etc/hotplug2.rules.bak /etc/hotplug2.rules
                killall hotplug2

                logger -st "$SCRIPT_TAG" "Restored original hotplug configuration"
            fi
        ;;
    esac
}

case "$1" in
    "run")
        if [ -n "$2" ] && [ -n "$3" ]; then # handles calls from hotplug
            lockfile lockwait "$2"

            case "$2" in
                "block"|"net"|"misc")
                    logger -st "$SCRIPT_TAG" "Running script (args: \"$2\" \"$3\")"
                ;;
            esac

            sh "$SCRIPT_PATH" event "$2" "$3"
            [ -n "$EXECUTE_COMMAND" ] && $EXECUTE_COMMAND "$2" "$3"

            lockfile unlock "$2"
        else # handles cron
            if ! grep -q "$SCRIPT_PATH" /etc/hotplug2.rules; then
                hotplug_config modify
            fi
        fi
    ;;
    "event")
        # $2 = subsystem, $3 = action
        case "$2" in
            "block")
                [ -x "$SCRIPT_DIR/usb-mount.sh" ] && sh "$SCRIPT_DIR/usb-mount.sh" hotplug
                [ -x "$SCRIPT_DIR/entware.sh" ] && sh "$SCRIPT_DIR/entware.sh" hotplug
            ;;
            "net")
                [ -x "$SCRIPT_DIR/usb-network.sh" ] && sh "$SCRIPT_DIR/usb-network.sh" hotplug
            ;;
            "misc")
                # empty for now
            ;;
        esac

        exit
    ;;
    "start")
        if [ -x "$SCRIPT_DIR/cron-queue.sh" ]; then
            sh "$SCRIPT_DIR/cron-queue.sh" add "$SCRIPT_NAME" "$SCRIPT_PATH run"
        else
            cru a "$SCRIPT_NAME" "*/1 * * * * $SCRIPT_PATH run"
        fi

        hotplug_config modify
    ;;
    "stop")
        [ -x "$SCRIPT_DIR/cron-queue.sh" ] && sh "$SCRIPT_DIR/cron-queue.sh" remove "$SCRIPT_NAME"
        cru d "$SCRIPT_NAME"

        hotplug_config restore
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
