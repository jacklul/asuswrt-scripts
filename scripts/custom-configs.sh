#!/bin/sh
# Made by Jack'lul <jacklul.github.io>
#
# Modify configuration files of some services
#
# Implements Custom config files feature from AsusWRT-Merlin:
#  https://github.com/RMerl/asuswrt-merlin.ng/wiki/Custom-config-files
#

# jacklul-asuswrt-scripts-update
#shellcheck disable=SC2155,SC2009

readonly SCRIPT_PATH="$(readlink -f "$0")"
readonly SCRIPT_NAME="$(basename "$SCRIPT_PATH" .sh)"
readonly SCRIPT_DIR="$(dirname "$SCRIPT_PATH")"
readonly SCRIPT_TAG="$(basename "$SCRIPT_PATH")"

ETC_FILES="profile hosts"
NOREPLACE_FILES="/etc/profile /etc/stubby/stubby.yml"
NOPOSTCONF_FILES="/etc/profile"

get_binary_location() {
    [ -z "$1" ] && { echo "Binary name not provided"; exit 1; }

    _BINARY_NAME="$(echo "$1"| awk '{print $1}')"

    case "$_BINARY_NAME" in
        "avahi-daemon"|"dnsmasq"|"minidlna"|"mt-daapd"|"nmbd"|"smbd"|"vsftpd")
            [ -f "/usr/sbin/$_BINARY_NAME" ] && echo "/usr/sbin/$_BINARY_NAME" && return
        ;;
    esac
}

restart_process() {
    [ -z "$1" ] && { echo "Process name not provided"; exit 1; }

    _STARTED=
    for PID in $(ps | grep "$1" | grep -v "grep\|/jffs/scripts" | awk '{print $1}'); do
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
        [ "$_FILE" = "$1" ] && return 1
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

    _BASENAME="$(basename "$1")"
    _NOREPLACE=false

    if ! is_file_replace_supported "$1"; then
        _NOREPLACE=true
    fi

    if [ -f "/jffs/configs/$_BASENAME" ] && [ "$_NOREPLACE" != true ]; then
        cat "/jffs/configs/$_BASENAME" > "$1.new"
    elif [ -f "/jffs/configs/$_BASENAME.add" ]; then
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
        logger -st "$SCRIPT_TAG" "Running /jffs/scripts/$_BASENAME.postconf script..."

        [ ! -f "$1" ] && touch "$1"
        sh "/jffs/scripts/$_BASENAME.postconf" "$1"
    fi
}

add_modified_mark() {
    [ -z "$1" ] && { echo "File path not provided"; exit 1; }

    echo "# Modified by $SCRIPT_NAME" >> "$1"
}

commit_new_file() {
    [ -z "$1" ] && { echo "File path not provided"; exit 1; }
    [ ! -f "$1" ] && { echo "File $1 does not exist"; exit 1; }
    [ !  -f "$1.new" ] && { echo "File $1.new does not exist"; exit 1; }

    cp -f "$1.new" "$1"

    logger -st "$SCRIPT_TAG" "Modified $1"
}

modify_service_config_file() {
    [ -z "$1" ] && { echo "File path not provided"; exit 1; }
    [ -z "$2" ] && { echo "Process name not provided"; exit 1; }
    [ -z "$3" ] && { echo "Service name not provided"; exit 1; }

    #debug_print "$1"

    if ps | grep -v "grep" | grep -q "$2" && [ -f "$1" ] && ! grep -q "# Modified by $SCRIPT_NAME" "$1"; then
        modify_config_file "$1"
        run_postconf_script "$1.new"

        if [ -f "$1.new" ]; then
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
    [ -z "$2" ] && { echo "Process name not provided"; exit 1; }
    [ -z "$3" ] && { echo "Service name not provided"; exit 1; }

    if ps | grep -v "grep" | grep -q "$2" && [ -f "$1.new" ]; then
        service "restart_$3" > /dev/null
        rm -f "$1.new"
        logger -st "$SCRIPT_TAG" "Restarted $3 service"
    fi
}

modify_etc_files() {
    for FILE in $ETC_FILES; do
        #debug_print "/etc/$FILE"

        if [ -f "/etc/$FILE" ] && ! grep -q "# Modified by $SCRIPT_NAME" "/etc/$FILE"; then
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
            logger -st "$SCRIPT_TAG" "Restored /etc/$FILE"
        fi
    done
}

debug_print() {
    [ -z "$1" ] && { echo "File path not provided"; exit 1; }

    echo "File: $1"

    is_file_replace_supported "$1" && echo "Replace supported"
    is_file_postconf_supported "$1" && echo "Postconf supported"

    echo ""
    echo ""
}

case "$1" in
    "run")
        if { [ ! -x "$SCRIPT_DIR/cron-queue.sh" ] || ! "$SCRIPT_DIR/cron-queue.sh" check "$SCRIPT_NAME" ; } && ! cru l | grep -q "#$SCRIPT_NAME#"; then
            exit
        fi

        modify_etc_files

        modify_service_config_file "/tmp/avahi/avahi-daemon.conf" "avahi-daemon" "avahi-daemon"
        modify_service_config_file "/etc/dnsmasq.conf" "dnsmasq" "dnsmasq"
        modify_service_config_file "/tmp/igmpproxy.conf" "igmpproxy" "igmpproxy"
        modify_service_config_file "/etc/minidlna.conf" "minidlna" "minidlna"
        modify_service_config_file "/etc/mt-daapd.conf" "mt-daapd" "mt-daapd"
        modify_service_config_file "/tmp/pptpd/pptpd.conf" "pptpd" "pptpd"
        modify_service_config_file "/etc/smb.conf" "nmbd\|smbd" "samba"
        modify_service_config_file "/tmp/snmpd.conf" "snmpd" "snmpd"
        modify_service_config_file "/etc/stubby/stubby.yml" "stubby" "stubby"
        modify_service_config_file "/etc/vsftpd.conf" "vsftpd" "vsftpd"
        modify_service_config_file "/etc/upnp/config" "miniupnpd" "upnp"
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

        restore_etc_files

        restore_service_config_file "/tmp/avahi/avahi-daemon.conf" "avahi-daemon" "avahi-daemon"
        restore_service_config_file "/etc/dnsmasq.conf" "dnsmasq" "dnsmasq"
        restore_service_config_file "/tmp/igmpproxy.conf" "igmpproxy" "igmpproxy"
        restore_service_config_file "/etc/minidlna.conf" "minidlna" "dms"
        restore_service_config_file "/etc/mt-daapd.conf" "mt-daapd" "mt_daapd"
        restore_service_config_file "/tmp/pptpd/pptpd.conf" "pptpd" "pptpd"
        restore_service_config_file "/etc/smb.conf" "nmbd\|smbd" "samba"
        restore_service_config_file "/tmp/snmpd.conf" "snmpd" "snmpd"
        restore_service_config_file "/etc/stubby/stubby.yml" "stubby" "stubby"
        restore_service_config_file "/etc/vsftpd.conf" "vsftpd" "ftpd"
        restore_service_config_file "/etc/upnp/config" "miniupnpd" "upnp"
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
