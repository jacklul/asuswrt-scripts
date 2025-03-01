#!/bin/sh
# Made by Jack'lul <jacklul.github.io>
#
# Modify configuration files of some services
#
# Implements Custom config files feature from Asuswrt-Merlin:
#  https://github.com/RMerl/asuswrt-merlin.ng/wiki/Custom-config-files
#

#jacklul-asuswrt-scripts-update=custom-configs.sh
#shellcheck disable=SC2155,SC2009

readonly SCRIPT_PATH="$(readlink -f "$0")"
readonly SCRIPT_NAME="$(basename "$SCRIPT_PATH" .sh)"
readonly SCRIPT_DIR="$(dirname "$SCRIPT_PATH")"
readonly SCRIPT_TAG="$(basename "$SCRIPT_PATH")"

ETC_FILES="profile hosts" # /etc files we can modify
NOREPLACE_FILES="/etc/profile /etc/stubby/stubby.yml" # files that cannot be replaced
NOPOSTCONF_FILES="/etc/profile" # files that cannot run postconf script

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
                #echo "File descriptor $_FD is already in use ($(readlink -f "/proc/$$/fd/$_FD"))"
                _FD=$((_FD+1))

                [ "$_FD" -gt "$_FD_MAX" ] && { echo "Failed to find available file descriptor"; exit 1; }
            done

            eval exec "$_FD>$_LOCKFILE"

            case "$1" in
                "lockwait")
                    _LOCK_WAITED=0
                    while ! flock -nx "$_FD"; do #flock -x "$_FD"
                        sleep 1
                        if [ "$_LOCK_WAITED" -ge 60 ]; then
                            echo "Failed to acquire a lock after 60 seconds"
                            exit 1
                        fi
                    done
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

get_binary_location() {
    [ -z "$1" ] && { echo "Binary name not provided"; exit 1; }

    _BINARY_NAME="$(echo "$1"| awk '{print $1}')"

    for _BASE_PATH in /usr/sbin /usr/bin /sbin /bin; do
        [ -f "$_BASE_PATH/$_BINARY_NAME" ] && echo "$_BASE_PATH/$_BINARY_NAME" && return
    done
}

restart_process() {
    [ -z "$1" ] && { echo "Process name not provided"; exit 1; }

    _STARTED=
    for PID in $(/bin/ps | grep "$1" | grep -v "grep\|/jffs/scripts" | awk '{print $1}'); do
        [ ! -f "/proc/$PID/cmdline" ] && continue
        _CMDLINE="$(tr "\0" " " < "/proc/$PID/cmdline")"

        killall "$1"
        [ -f "/proc/$PID/cmdline" ] && kill -s SIGTERM "$PID" 2> /dev/null
        [ -f "/proc/$PID/cmdline" ] && kill -s SIGKILL "$PID" 2> /dev/null

        if [ -z "$_STARTED" ]; then
            # make sure we are executing build-in binary
            _FULL_BINARY_PATH=
            if [ "$(echo "$_CMDLINE" | cut -c1-1)" != "/" ]; then
                _FULL_BINARY_PATH="$(get_binary_location "$_CMDLINE")"
            fi

            if [ -n "$_FULL_BINARY_PATH" ]; then
                _CMDLINE="$(echo "$_CMDLINE" | awk '{for (i=2; i<NF; i++) printf $i " "; print $NF}')"

                #shellcheck disable=SC2086
                "$_FULL_BINARY_PATH" $_CMDLINE && _STARTED=1 && logger -st "$SCRIPT_TAG" "Restarted process: $_FULL_BINARY_PATH $_CMDLINE"
            else
                $_CMDLINE && _STARTED=1 && logger -st "$SCRIPT_TAG" "Restarted process: $_CMDLINE"
            fi
        fi
    done
}

is_file_replace_supported() {
    [ -z "$1" ] && { echo "File path not provided"; exit 1; }

    for _FILE in $NOREPLACE_FILES; do
        [ "$_FILE" = "$(echo "$1" | sed 's/\.new$//')" ] && return 1
    done

    return 0
}

is_file_postconf_supported() {
    [ -z "$1" ] && { echo "File path not provided"; exit 1; }

    for _FILE in $NOPOSTCONF_FILES; do
        [ "$_FILE" = "$1" ] && return 1
    done

    return 0
}

is_config_file_modified() {
    [ -z "$1" ] && { echo "File path not provided"; exit 1; }
    [ ! -f "$1" ] && { echo "File $1 does not exist"; return 1; }
    [ ! -f "$1.new" ] && { echo "File $1.new does not exist"; return 1; }

    if [ "$(md5sum "$1" | awk '{print $1}')" != "$(md5sum "$1.new" | awk '{print $1}')" ]; then
        return 0
    fi

    return 1
}

modify_config_file() {
    [ -z "$1" ] && { echo "File path not provided"; exit 1; }
    # $2 = custom /jffs/configs/[NAME.conf]

    if [ -n "$2" ]; then
        _BASENAME="$2"
    else
        _BASENAME="$(basename "$1")"
    fi

    if [ -f "/jffs/configs/$_BASENAME" ] && is_file_replace_supported "$1"; then
        logger -st "$SCRIPT_TAG" "Replacing '$1' with '/jffs/configs/$_BASENAME'..."

        cat "/jffs/configs/$_BASENAME" > "$1.new"
    elif [ -f "/jffs/configs/$_BASENAME.add" ]; then
        logger -st "$SCRIPT_TAG" "Appending '/jffs/configs/$_BASENAME.add' to '$1'..."

        cp "$1" "$1.new"
        cat "/jffs/configs/$_BASENAME.add" >> "$1.new"
    fi
}

run_postconf_script() {
    [ -z "$1" ] && { echo "File path not provided"; exit 1; }

    if ! is_file_postconf_supported "$1"; then
        return
    fi

    _BASENAME="$(basename "$1" | cut -d. -f1)"

    if [ -x "/jffs/scripts/$_BASENAME.postconf" ]; then
        logger -st "$SCRIPT_TAG" "Running '/jffs/scripts/$_BASENAME.postconf' script..."

        [ ! -f "$1.new" ] && cp "$1" "$1.new"
        sh "/jffs/scripts/$_BASENAME.postconf" "$1.new"
    fi
}

add_modified_mark() {
    [ -z "$1" ] && { echo "File path not provided"; exit 1; }

    _BASENAME="$(basename "$1" | cut -d. -f1)"
    _COMMENT="#"

    case "$_BASENAME" in
        "zebra")
            _COMMENT="!"
        ;;
    esac

    echo "" >> "$1"
    echo "$_COMMENT Modified by $SCRIPT_NAME script" >> "$1"
}

commit_new_file() {
    [ -z "$1" ] && { echo "File path not provided"; exit 1; }
    [ ! -f "$1" ] && { echo "File $1 does not exist"; exit 1; }
    [ !  -f "$1.new" ] && { echo "File $1.new does not exist"; exit 1; }

    cp -f "$1.new" "$1"
}

modify_service_config_file() {
    [ -z "$1" ] && { echo "File path not provided"; exit 1; }
    [ -z "$2" ] && { echo "Process match expression not provided"; exit 1; }
    [ -z "$3" ] && { echo "Process binary name not provided"; exit 1; }
    # $4 = custom /jffs/configs/[NAME.conf]

    if /bin/ps | grep -v "grep" | grep -q "$2" && [ -f "$1" ] && ! grep -q "Modified by $SCRIPT_NAME script" "$1"; then
        if [ -n "$4" ]; then
            modify_config_file "$1" "$4"
        else
            modify_config_file "$1"
        fi

        run_postconf_script "$1"

        if [ -f "$1.new" ] && [ "$(md5sum "$1" | awk '{print $1}')" != "$(md5sum "$1.new" | awk '{print $1}')" ]; then
            add_modified_mark "$1.new"

            if is_config_file_modified "$1"; then
                commit_new_file "$1"

                case "$3" in
                    "avahi-daemon")
                        /usr/sbin/avahi-daemon --kill && /usr/sbin/avahi-daemon -D && logger -st "$SCRIPT_TAG" "Restarted process: avahi-daemon"
                    ;;
                    "samba")
                        restart_process nmbd
                        restart_process smbd
                    ;;
                    "ipsec")
                        ipsec restart > /dev/null 2>&1
                    ;;
                    "mcpd")
                        killall -SIGKILL /bin/mcpd 2> /dev/null
                        nohup /bin/mcpd > /dev/null 2>&1 &
                    ;;
                    *)
                        restart_process "$3"
                    ;;
                esac
            fi
        fi
    fi
}

restore_service_config_file() {
    [ -z "$1" ] && { echo "File path not provided"; exit 1; }
    [ -z "$2" ] && { echo "Process match expression not provided"; exit 1; }
    [ -z "$3" ] && { echo "Service name not provided"; exit 1; }

    if /bin/ps | grep -v "grep" | grep -q "$2" && [ -f "$1.new" ]; then
        case "$3" in
            "ipsec")
                service "ipsec_restart" > /dev/null
            ;;
            *)
                service "restart_$3" > /dev/null
            ;;
        esac

        rm -f "$1.new"

        logger -st "$SCRIPT_TAG" "Restarted service: $3"
    fi
}

modify_etc_files() {
    for FILE in $ETC_FILES; do
        if [ -f "/etc/$FILE" ] && ! grep -q "Modified by $SCRIPT_NAME script" "/etc/$FILE"; then
            [ ! -f "/etc/$FILE.bak" ] && cp "/etc/$FILE" "/etc/$FILE.bak"

            modify_config_file "/etc/$FILE"

            if [ -f "/etc/$FILE.new" ]; then
                add_modified_mark "/etc/$FILE.new"
                is_config_file_modified "/etc/$FILE" && commit_new_file "/etc/$FILE"
            fi
        fi
    done
}

restore_etc_files() {
    for FILE in $ETC_FILES; do
        if  [ -f "/etc/$FILE.bak" ] && [ -f "/etc/$FILE.new" ]; then
            cp -f "/etc/$FILE.bak" "/etc/$FILE"
            rm -f "/etc/$FILE.new"
            logger -st "$SCRIPT_TAG" "Restored: /etc/$FILE"
        fi
    done
}

configs() {
    lockfile lockwait # not lockfail as multiple service restarts might queue this one up via service-event.sh

    case "$1" in
        "modify")
            # services.c
            modify_etc_files # profile, hosts
            modify_service_config_file "/etc/dnsmasq.conf" "dnsmasq" "dnsmasq"
            modify_service_config_file "/etc/stubby/stubby.yml" "stubby" "stubby"
            # inadyn.conf - currently no way to support this as it is not running as daemon
            modify_service_config_file "/var/mcpd.conf" "mcpd" "mcpd"
            modify_service_config_file "/etc/upnp/config" "miniupnpd" "miniupnpd" "upnp"
            modify_service_config_file "/tmp/avahi/avahi-daemon.conf" "avahi-daemon" "avahi-daemon"
            # afpd.service, adisk.service, mt-daap.service - use avahi-daemon.postconf to modify these
            modify_service_config_file "/etc/zebra.conf" "zebra" "zebra"
            modify_service_config_file "/etc/ripd.conf" "ripd" "ripd"
            modify_service_config_file "/tmp/torrc" "tor" "tor"

            # wan.c
            modify_service_config_file "/tmp/igmpproxy.conf" "igmpproxy" "igmpproxy"

            # snmpd.c
            modify_service_config_file "/tmp/snmpd.conf" "snmpd" "snmpd"

            # usb.c
            modify_service_config_file "/etc/vsftpd.conf" "vsftpd" "vsftpd"
            modify_service_config_file "/etc/smb.conf" "nmbd\|smbd" "samba"
            modify_service_config_file "/etc/minidlna.conf" "minidlna" "minidlna"
            modify_service_config_file "/etc/mt-daapd.conf" "mt-daapd" "mt-daapd"

            # vpn.c
            modify_service_config_file "/tmp/pptpd/pptpd.conf" "pptpd" "pptpd"

            # rc_ipsec.c
            modify_service_config_file "/etc/ipsec.conf" "ipsec" "ipsec"
        ;;
        "restore")
            # services.c
            restore_etc_files
            restore_service_config_file "/etc/dnsmasq.conf" "dnsmasq" "dnsmasq"
            restore_service_config_file "/etc/stubby/stubby.yml" "stubby" "stubby"
            # inadyn.conf
            restore_service_config_file "/var/mcpd.conf" "mcpd" "wan"
            restore_service_config_file "/etc/upnp/config" "miniupnpd" "upnp"
            restore_service_config_file "/tmp/avahi/avahi-daemon.conf" "avahi-daemon" "mdns"
            # afpd.service, adisk.service, mt-daap.service
            restore_service_config_file "/etc/zebra.conf" "zebra" "quagga"
            restore_service_config_file "/etc/ripd.conf" "ripd" "quagga"
            restore_service_config_file "/tmp/torrc" "tor" "tor"

            # wan.c
            restore_service_config_file "/tmp/igmpproxy.conf" "igmpproxy" "wan_line"

            # snmpd.c
            restore_service_config_file "/tmp/snmpd.conf" "snmpd" "snmpd"

            # usb.c
            restore_service_config_file "/etc/vsftpd.conf" "vsftpd" "ftpd"
            restore_service_config_file "/etc/smb.conf" "nmbd\|smbd" "samba"
            restore_service_config_file "/etc/minidlna.conf" "minidlna" "dms"
            restore_service_config_file "/etc/mt-daapd.conf" "mt-daapd" "mt_daapd"

            # vpn.c
            restore_service_config_file "/tmp/pptpd/pptpd.conf" "pptpd" "pptpd"

            # rc_ipsec.c
            restore_service_config_file "/etc/ipsec.conf" "ipsec" "ipsec"
        ;;
    esac

    lockfile unlock
}

case "$1" in
    "run")
        if { [ ! -x "$SCRIPT_DIR/cron-queue.sh" ] || ! "$SCRIPT_DIR/cron-queue.sh" check "$SCRIPT_NAME" ; } && ! cru l | grep -q "#$SCRIPT_NAME#"; then
            exit # do not run if not started
        fi

        configs modify
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

        configs restore
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
