#!/bin/sh
# Made by Jack'lul <jacklul.github.io>
#
# Modify configuration files of some services
#
# Implements Custom config files feature from AsusWRT-Merlin:
#  https://github.com/RMerl/asuswrt-merlin.ng/wiki/Custom-config-files
#

#shellcheck disable=SC2155,SC2009

readonly SCRIPT_PATH="$(readlink -f "$0")"
readonly SCRIPT_NAME="$(basename "$SCRIPT_PATH" .sh)"
readonly SCRIPT_DIR="$(dirname "$SCRIPT_PATH")"
readonly SCRIPT_CONFIG="$SCRIPT_DIR/$SCRIPT_NAME.conf"
readonly SCRIPT_TAG="$(basename "$SCRIPT_PATH")"

if [ -f "$SCRIPT_CONFIG" ]; then
    #shellcheck disable=SC1090
    . "$SCRIPT_CONFIG"
fi

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
    for PID in $(ps | grep "$1" | grep -v "grep" | awk '{print $1}'); do
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

modify_config_file() {
    [ -z "$1" ] && { echo "File name not provided"; exit 1; }

    _BASENAME="$(basename "$1")"

    if [ -f "/jffs/configs/$_BASENAME" ] && [ "$2" != "noreplace" ]; then
        cat "/jffs/configs/$_BASENAME" > "$1.new"
    elif [ -f "/jffs/configs/$_BASENAME.add" ]; then
        cp "$1" "$1.new"
        cat "/jffs/configs/$_BASENAME.add" >> "$1.new"
    fi
}

run_postconf_script() {
    [ -z "$1" ] && { echo "File name not provided"; exit 1; }

    _BASENAME="$(basename "$1" | cut -d. -f1)"

    if [ -x "/jffs/scripts/$_BASENAME.postconf" ]; then
        logger -st "$SCRIPT_TAG" "Running /jffs/scripts/$_BASENAME.postconf script..."

        [ ! -f "$1" ] && touch "$1"
        sh "/jffs/scripts/$_BASENAME.postconf" "$1"
    fi
}

is_config_file_modified() {
    [ -z "$1" ] && { echo "File name not provided"; exit 1; }
    [ ! -f "$1" ] && { echo "File $1 does not exist"; return 1; }
    [ ! -f "$1.new" ] && { echo "File $1.new does not exist"; return 1; }

    if [ "$(md5sum "$1" | awk '{print $1}')" != "$(md5sum "$1.new" | awk '{print $1}')" ]; then
        return 0
    fi

    return 1
}

add_modified_mark() {
    [ -z "$1" ] && { echo "File name not provided"; exit 1; }

    echo "# Modified by $SCRIPT_NAME" >> "$1"
}

commit_new_file() {
    [ -z "$1" ] && { echo "File name not provided"; exit 1; }
    [ ! -f "$1" ] && { echo "File $1 does not exist"; exit 1; }
    [ !  -f "$1.new" ] && { echo "File $1.new does not exist"; exit 1; }

    cp -f "$1.new" "$1"

    logger -st "$SCRIPT_TAG" "Modified $1"
}

case "$1" in
    "run")
        cru l | grep -q "#$SCRIPT_NAME#" || exit

        if [ -f /etc/profile ] && ! grep -q "# Modified by $SCRIPT_NAME" /etc/profile; then
            [ ! -f /etc/profile.bak ] && cp /etc/profile /etc/profile.bak

            modify_config_file /etc/profile noreplace

            if [ -f /etc/profile.new ]; then
                add_modified_mark /etc/profile.new
                is_config_file_modified /etc/profile && commit_new_file /etc/profile
            fi
        fi

        if [ -f /etc/hosts ] && ! grep -q "# Modified by $SCRIPT_NAME" /etc/hosts; then
            [ ! -f /etc/hosts.bak ] && cp /etc/hosts /etc/hosts.bak

            modify_config_file /etc/hosts noreplace

            if [ -f /etc/hosts.new ]; then
                add_modified_mark /etc/hosts.new
                is_config_file_modified /etc/hosts && commit_new_file /etc/hosts
            fi
        fi

        if ps | grep -v "grep" | grep -q "avahi-daemon" && [ -f /tmp/avahi/avahi-daemon.conf ] && ! grep -q "# Modified by $SCRIPT_NAME" /tmp/avahi/avahi-daemon.conf; then
            modify_config_file /tmp/avahi/avahi-daemon.conf
            run_postconf_script /tmp/avahi/avahi-daemon.conf.new

            if [ -f /tmp/avahi/avahi-daemon.conf.new ]; then
                add_modified_mark /tmp/avahi/avahi-daemon.conf.new

                if is_config_file_modified /tmp/avahi/avahi-daemon.conf; then
                    commit_new_file /tmp/avahi/avahi-daemon.conf

                    /usr/sbin/avahi-daemon --kill && /usr/sbin/avahi-daemon -D && logger -st "$SCRIPT_TAG" "Restarted process: avahi-daemon"
                fi
            fi
        fi

        if ps | grep -v "grep" | grep -q "dnsmasq" && [ -f /etc/dnsmasq.conf ] && ! grep -q "# Modified by $SCRIPT_NAME" /etc/dnsmasq.conf; then
            modify_config_file /etc/dnsmasq.conf
            run_postconf_script /etc/dnsmasq.conf.new

            if [ -f /etc/dnsmasq.conf.new ]; then
                add_modified_mark /etc/dnsmasq.conf.new

                if is_config_file_modified /etc/dnsmasq.conf; then
                    cp -f /etc/dnsmasq.conf.new /etc/dnsmasq.conf

                    logger -st "$SCRIPT_TAG" "Modified /etc/dnsmasq.conf"

                    restart_process dnsmasq
                fi
            fi
        fi

        if ps | grep -v "grep" | grep -q "minidlna" && [ -f /etc/minidlna.conf ] && ! grep -q "# Modified by $SCRIPT_NAME" /etc/minidlna.conf; then
            modify_config_file /etc/minidlna.conf
            run_postconf_script /etc/minidlna.conf.new

            if [ -f /etc/minidlna.conf.new ]; then
                add_modified_mark /etc/minidlna.conf.new

                if is_config_file_modified /etc/minidlna.conf; then
                    commit_new_file /etc/minidlna.conf

                    restart_process minidlna
                fi
            fi
        fi

        if ps | grep -v "grep" | grep -q "mt-daapd" && [ -f /etc/mt-daapd.conf ] && ! grep -q "# Modified by $SCRIPT_NAME" /etc/mt-daapd.conf; then
            modify_config_file /etc/mt-daapd.conf
            run_postconf_script /etc/mt-daapd.conf.new

            if [ -f /etc/mt-daapd.conf.new ]; then
                add_modified_mark /etc/mt-daapd.conf.new

                if is_config_file_modified /etc/mt-daapd.conf; then
                    commit_new_file /etc/mt-daapd.conf

                    restart_process mt-daapd
                fi
            fi
        fi

        if ps | grep -v "grep" | grep -q "nmbd\|smbd" && [ -f /etc/smb.conf ] && ! grep -q "# Modified by $SCRIPT_NAME" /etc/smb.conf; then
            modify_config_file /etc/smb.conf
            run_postconf_script /etc/smb.conf.new

            if [ -f /etc/smb.conf.new ]; then
                add_modified_mark /etc/smb.conf.new

                if is_config_file_modified /etc/smb.conf; then
                   commit_new_file /etc/smb.conf

                    restart_process nmbd
                    restart_process smbd
                fi
            fi
        fi

        if ps | grep -v "grep" | grep -q "vsftpd" && [ -f /etc/vsftpd.conf ] && ! grep -q "# Modified by $SCRIPT_NAME" /etc/vsftpd.conf; then
            modify_config_file /etc/vsftpd.conf
            run_postconf_script /etc/vsftpd.conf.new

            if [ -f /etc/vsftpd.conf.new ]; then
                add_modified_mark /etc/vsftpd.conf.new

                if is_config_file_modified /etc/vsftpd.conf; then
                    commit_new_file /etc/vsftpd.conf

                    # we need background=YES to correctly restart the process without blocking the script
                    ! grep -q "background=" /etc/vsftpd.conf && sed -i "/listen=/abackground=YES" /etc/vsftpd.conf

                    if grep -q "background=YES" /etc/vsftpd.conf; then
                        restart_process vsftpd
                    else
                        logger -st "$SCRIPT_TAG" "Unable to restart vsftpd process - \"background=YES\" not found in the config file"
                    fi
                fi
            fi
        fi
    ;;
    "start")
        cru a "$SCRIPT_NAME" "*/1 * * * * $SCRIPT_PATH run"

        sh "$SCRIPT_PATH" run
    ;;
    "stop")
        cru d "$SCRIPT_NAME"

        if  [ -f /etc/profile.bak ] && [ -f /etc/profile.new ]; then
            cp -f /etc/profile.bak /etc/profile
            rm -f /etc/profile.new
            logger -st "$SCRIPT_TAG" "Restored /etc/profile"
        fi

        if  [ -f /etc/hosts.bak ] && [ -f /etc/hosts.new ]; then
            cp -f /etc/hosts.bak /etc/hosts
            rm -f /etc/hosts.new
            logger -st "$SCRIPT_TAG" "Restored /etc/hosts"
        fi

        if ps | grep -v "grep" | grep -q "avahi-daemon" && [ -f /tmp/avahi/avahi-daemon.conf.new ]; then
            service restart_mdns > /dev/null
            rm -f /tmp/avahi/avahi-daemon.conf.new
            logger -st "$SCRIPT_TAG" "Restarted avahi-daemon service"
        fi

        if ps | grep -v "grep" | grep -q "dnsmasq" && [ -f /etc/dnsmasq.conf.new ]; then
            service restart_dnsmasq > /dev/null
            rm -f /etc/dnsmasq.conf.new
            logger -st "$SCRIPT_TAG" "Restarted dnsmasq service"
        fi

        if ps | grep -v "grep" | grep -q "minidlna" && [ -f /etc/minidlna.conf.new ]; then
            service restart_media > /dev/null
            rm -f /etc/minidlna.conf.new
            logger -st "$SCRIPT_TAG" "Restarted minidlna service"
        fi

        if ps | grep -v "grep" | grep -q "mt-daapd" && [ -f /etc/mt-daapd.conf.new ]; then
            service restart_media > /dev/null
            rm -f /etc/mt-daapd.conf.new
            logger -st "$SCRIPT_TAG" "Restarted mt-daapd service"
        fi

        if ps | grep -v "grep" | grep -q "nmbd\|smbd" && [ -f /etc/smb.conf.new ]; then
            service restart_samba > /dev/null
            rm -f /etc/smb.conf.new
            logger -st "$SCRIPT_TAG" "Restarted samba service"
        fi

        if ps | grep -v "grep" | grep -q "vsftpd" && [ -f /etc/vsftpd.conf.new ]; then
            service restart_ftpd > /dev/null
            rm -f /etc/vsftpd.conf.new
            logger -st "$SCRIPT_TAG" "Restarted ftpd service"
        fi
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
