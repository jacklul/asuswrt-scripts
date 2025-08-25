#!/bin/sh
# Made by Jack'lul <jacklul.github.io>
#
# Automatically mounts any USB storage
#

#jacklul-asuswrt-scripts-update=usb-mount.sh
#shellcheck disable=SC2155

readonly script_path="$(readlink -f "$0")"
readonly script_name="$(basename "$script_path" .sh)"
readonly script_dir="$(dirname "$script_path")"
readonly script_config="$script_dir/$script_name.conf"

EXECUTE_COMMAND="" # execute a command each time status changes (receives arguments: $1 = action, $2 = device)
RUN_EVERY_MINUTE= # check for new devices to mount periodically (true/false), empty means false when hotplug-event.sh is available but otherwise true

if [ -f "$script_config" ]; then
    #shellcheck disable=SC1090
    . "$script_config"
fi

if [ -z "$RUN_EVERY_MINUTE" ]; then
    [ ! -x "$script_dir/hotplug-event.sh" ] && RUN_EVERY_MINUTE=true
fi

lockfile() { #LOCKFILE_START#
    [ -z "$script_name" ] && script_name="$(basename "$0" .sh)"

    _lockfile="/var/lock/script-$script_name.lock"
    _pidfile="/var/run/script-$script_name.pid"
    _fd_min=100
    _fd_max=200

    if [ -n "$2" ]; then
        _lockfile="/var/lock/script-$script_name-$2.lock"
        _pidfile="/var/run/script-$script_name-$2.lock"
    fi

    [ -n "$3" ] && _fd_min="$3" && _fd_max="$3"
    [ -n "$4" ] && _fd_max="$4"

    [ ! -d /var/lock ] && { mkdir -p /var/lock || exit 1; }
    [ ! -d /var/run ] && { mkdir -p /var/run || exit 1; }

    _lockpid=
    [ -f "$_pidfile" ] && _lockpid="$(cat "$_pidfile")"

    case "$1" in
        "lockwait"|"lockfail"|"lockexit")
            for _fd_test in "/proc/$$/fd"/*; do
                if [ "$(readlink -f "$_fd_test")" = "$_lockfile" ]; then
                    logger -st "$script_name" "File descriptor ($(basename "$_fd_test")) is already open for the same lockfile ($_lockfile)"
                    exit 1
                fi
            done

            _fd=$(lockfile_fd "$_fd_min" "$_fd_max")
            eval exec "$_fd>$_lockfile"

            case "$1" in
                "lockwait")
                    _lockwait=0
                    while ! flock -nx "$_fd"; do
                        eval exec "$_fd>&-"
                        _lockwait=$((_lockwait+1))

                        if [ "$_lockwait" -ge 60 ]; then
                            logger -st "$script_name" "Failed to acquire a lock after 60 seconds ($_lockfile)"
                            exit 1
                        fi

                        sleep 1
                        _fd=$(lockfile_fd "$_fd_min" "$_fd_max")
                        eval exec "$_fd>$_lockfile"
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
}

lockfile_fd() {
    _lfd_min=$1
    _lfd_max=$2

    while [ -f "/proc/$$/fd/$_lfd_min" ]; do
        _lfd_min=$((_lfd_min+1))
        [ "$_lfd_min" -gt "$_lfd_max" ] && { logger -st "$script_name" "Error: No free file descriptors available"; exit 1; }
    done

    echo "$_lfd_min"
} #LOCKFILE_END#

is_asusware_mounting() {
    _apps_autorun="$(nvram get apps_state_autorun)"

    if [ "$_apps_autorun" != "" ] && [ "$_apps_autorun" != "4" ]; then
        _vars_to_check="apps_state_install apps_state_remove apps_state_switch apps_state_stop apps_state_enable apps_state_update apps_state_upgrade"

        for _var in $_vars_to_check; do
            _value="$(nvram get "$_var")"

            if [ "$_value" != "" ] && [ "$_value" != "0" ]; then
                return 1
            fi
        done

        return 0
    fi

    return 1
}

setup_mount() {
    [ -z "$2" ] && { echo "You must specify a device"; exit 1; }

    if is_asusware_mounting; then
        logger -st "$script_name" "Ignoring call because Asusware is mounting (args: '$1' '$2')"
        exit
    fi

    lockfile lockwait

    _device="/dev/$2"
    _mountpoint="/tmp/mnt/$2"

    case "$1" in
        "add")
            [ ! -b "$_device" ] && return

            if ! mount | grep -Fq "$_mountpoint"; then
                mkdir -p "$_mountpoint"

                #shellcheck disable=SC2086
                if mount "$_device" "$_mountpoint"; then
                    logger -st "$script_name" "Mounted '$_device' on '$_mountpoint'"
                else
                    rmdir "$_mountpoint"
                    logger -st "$script_name" "Failed to mount '$_device' on '$_mountpoint'"
                fi
            fi
        ;;
        "remove")
            if mount | grep -Fq "$_mountpoint"; then
                if [ "$(mount | grep -Fc "$_device")" -gt 1 ]; then
                    logger -st "$script_name" "Unable to unmount '$_mountpoint' - device '$_device' is used by another mount"
                else
                    if umount "$_mountpoint"; then
                        rmdir "$_mountpoint"
                        logger -st "$script_name" "Unmounted '$_device' from '$_mountpoint'"
                    else
                        logger -st "$script_name" "Failed to unmount '$_device' from '$_mountpoint'"
                    fi
                fi
            fi
        ;;
    esac

    # no extra condition needed, already handled outside this function
    [ -n "$EXECUTE_COMMAND" ] && $EXECUTE_COMMAND "$1" "$_device"

    lockfile unlock
}

case "$1" in
    "run")
        for device in /dev/sd*; do
            [ ! -b "$device" ] && continue

            devicename="$(basename "$device")"

            if [ ! -d "/tmp/mnt/$devicename" ]; then
                setup_mount add "$devicename"
            fi
        done
    ;;
    "hotplug")
        #shellcheck disable=SC2153
        if [ "$SUBSYSTEM" = "block" ] && [ -n "$DEVICENAME" ]; then
            case "$ACTION" in
                "add")
                    setup_mount add "$DEVICENAME"
                ;;
                "remove")
                    setup_mount remove "$DEVICENAME"
                ;;
            esac
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

        for device in /dev/sd*; do
            [ -b "$device" ] && setup_mount add "$(basename "$device")"
        done
    ;;
    "stop")
        [ -x "$script_dir/cron-queue.sh" ] && sh "$script_dir/cron-queue.sh" remove "$script_name"
        cru d "$script_name"

        for device in /dev/sd*; do
            [ -b "$device" ] && setup_mount remove "$(basename "$device")"
        done
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
