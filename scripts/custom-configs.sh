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

    _NAME="$1"
    _STARTED=
    for PID in $(ps | grep "$_NAME" | grep -v "grep" | awk '{print $1}'); do
        [ ! -f "/proc/$PID/cmdline" ] && continue
        _CMDLINE="$(tr "\0" " " < "/proc/$PID/cmdline")"

        echo "$_CMDLINE"

        killall "$_NAME"
        [ -f "/proc/$PID/cmdline" ] && kill -s SIGTERM "$PID" 2>/dev/null
        [ -f "/proc/$PID/cmdline" ] && kill -s SIGKILL "$PID" 2>/dev/null

        echo "progress"

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

run_postconf_script() {
    [ -z "$1" ] && { echo "File name not provided"; exit 1; }

    _SCRIPT="$(basename "$1" | cut -d. -f1)"

    if [ -x "$SCRIPT_DIR/$_SCRIPT.postconf" ]; then
        logger -st "$SCRIPT_TAG" "Running $SCRIPT_DIR/$_SCRIPT.postconf script..."
        sh "$SCRIPT_DIR/$_SCRIPT.postconf" "$1"
    fi
}

case "$1" in
    "run")
        cru l | grep -q "#$SCRIPT_NAME#" || exit

        if [ -f /etc/profile ] && ! grep -q "# Modified by $SCRIPT_NAME" /etc/profile; then
            [ ! -f /etc/profile.bak ] && cp /etc/profile /etc/profile.bak

            if [ -f /jffs/configs/profile.add ]; then
                cp /etc/profile /etc/profile.new
                cat /jffs/configs/profile.add >> /etc/profile.new
            fi

            if [ -f /etc/profile.new ]; then
                echo "# Modified by $SCRIPT_NAME" >> /etc/profile.new

                if [ "$(md5sum /etc/profile | awk '{print $1}')" != "$(md5sum /etc/profile.new | awk '{print $1}')" ]; then
                    cp -f /etc/profile.new /etc/profile

                    logger -st "$SCRIPT_TAG" "Modified /etc/profile"
                fi
            fi
        fi

        if ps | grep -v "grep" | grep -q "avahi-daemon" && [ -f /tmp/avahi/avahi-daemon.conf ] && ! grep -q "# Modified by $SCRIPT_NAME" /tmp/avahi/avahi-daemon.conf; then
            if [ -f /jffs/configs/avahi-daemon.conf ]; then
                cp /tmp/avahi/avahi-daemon.conf /tmp/avahi/avahi-daemon.conf.new
                cat /jffs/configs/avahi-daemon.conf > /tmp/avahi/vsftpd.conf.new
            elif [ -f /jffs/configs/avahi-daemon.conf.add ]; then
                cp /tmp/avahi/avahi-daemon.conf /tmp/avahi/avahi-daemon.conf.new
                cat /jffs/configs/avahi-daemon.conf.add >> /tmp/avahi/avahi-daemon.conf.new
            fi

            if [ -f /tmp/avahi/avahi-daemon.conf.new ]; then
                echo "# Modified by $SCRIPT_NAME" >> /tmp/avahi/avahi-daemon.conf.new
                run_postconf_script /tmp/avahi/avahi-daemon.conf.new

                if [ "$(md5sum /tmp/avahi/avahi-daemon.conf | awk '{print $1}')" != "$(md5sum /tmp/avahi/avahi-daemon.conf.new | awk '{print $1}')" ]; then
                    cp -f /tmp/avahi/avahi-daemon.conf.new /tmp/avahi/avahi-daemon.conf

                    logger -st "$SCRIPT_TAG" "Modified /tmp/avahi/avahi-daemon.conf"

                    avahi-daemon --kill && avahi-daemon -D && logger -st "$SCRIPT_TAG" "Restarted process: avahi-daemon"
                fi
            fi
        fi

        if ps | grep -v "grep" | grep -q "dnsmasq" && [ -f /etc/dnsmasq.conf ] && ! grep -q "# Modified by $SCRIPT_NAME" /etc/dnsmasq.conf; then
            if [ -f /jffs/configs/dnsmasq.conf ]; then
                cp /etc/dnsmasq.conf /etc/dnsmasq.conf.new
                cat /jffs/configs/dnsmasq.conf > /etc/dnsmasq.conf.new
            elif [ -f /jffs/configs/dnsmasq.conf.add ]; then
                cp /etc/dnsmasq.conf /etc/dnsmasq.conf.new
                cat /jffs/configs/dnsmasq.conf.add >> /etc/dnsmasq.conf.new
            fi

            if [ -f /etc/dnsmasq.conf.new ]; then
                echo "# Modified by $SCRIPT_NAME" >> /etc/dnsmasq.conf.new
                run_postconf_script /etc/dnsmasq.conf.new

                if [ "$(md5sum /etc/dnsmasq.conf | awk '{print $1}')" != "$(md5sum /etc/dnsmasq.conf.new | awk '{print $1}')" ]; then
                    cp -f /etc/dnsmasq.conf.new /etc/dnsmasq.conf

                    logger -st "$SCRIPT_TAG" "Modified /etc/dnsmasq.conf"

                    restart_process dnsmasq
                fi
            fi
        fi

        if ps | grep -v "grep" | grep -q "nmbd\|smbd" && [ -f /etc/smb.conf ] && ! grep -q "# Modified by $SCRIPT_NAME" /etc/smb.conf; then
            if [ -f /jffs/configs/smb.conf ]; then
                cp /etc/smb.conf /etc/smb.conf.new
                cat /jffs/configs/smb.conf > /etc/smb.conf.new
            elif [ -f /jffs/configs/smb.conf.add ]; then
                cp /etc/smb.conf /etc/smb.conf.new
                cat /jffs/configs/smb.conf.add >> /etc/smb.conf.new
            fi

            if [ -f /etc/smb.conf.new ]; then
                echo "# Modified by $SCRIPT_NAME" >> /etc/smb.conf.new
                run_postconf_script /etc/smb.conf.new

                if [ "$(md5sum /etc/smb.conf | awk '{print $1}')" != "$(md5sum /etc/smb.conf.new | awk '{print $1}')" ]; then
                    cp -f /etc/smb.conf.new /etc/smb.conf

                    logger -st "$SCRIPT_TAG" "Modified /etc/smb.conf"

                    # Causes debug logging in syslog?
                    #for PID in $(ps | grep nmbd | grep -v "grep" | awk '{print $1}'); do
                    #    kill -s SIGHUP "$PID"
                    #done
                    #for PID in $(ps | grep smbd | grep -v "grep" | awk '{print $1}'); do
                    #    kill -s SIGHUP "$PID"
                    #done

                    restart_process nmbd
                    restart_process smbd
                fi
            fi
        fi

        if ps | grep -v "grep" | grep -q "vsftpd" && [ -f /etc/vsftpd.conf ] && ! grep -q "# Modified by $SCRIPT_NAME" /etc/vsftpd.conf; then
            if [ -f /jffs/configs/vsftpd.conf ]; then
                cp /etc/vsftpd.conf /etc/vsftpd.conf.new
                cat /jffs/configs/vsftpd.conf > /etc/vsftpd.conf.new
            elif [ -f /jffs/configs/vsftpd.conf.add ]; then
                cp /etc/vsftpd.conf /etc/vsftpd.conf.new
                cat /jffs/configs/vsftpd.conf.add >> /etc/vsftpd.conf.new
            fi

            if [ -f /etc/vsftpd.conf.new ]; then
                echo "# Modified by $SCRIPT_NAME" >> /etc/vsftpd.conf.new
                run_postconf_script /etc/vsftpd.conf.new

                if [ "$(md5sum /etc/vsftpd.conf | awk '{print $1}')" != "$(md5sum /etc/vsftpd.conf.new | awk '{print $1}')" ]; then
                    cp -f /etc/vsftpd.conf.new /etc/vsftpd.conf

                    logger -st "$SCRIPT_TAG" "Modified /etc/vsftpd.conf"

                    # Causes debug logging in syslog?
                    #for PID in $(ps | grep vsftpd | grep -v "grep" | awk '{print $1}'); do
                    #    kill -s SIGHUP "$PID"
                    #done

                    restart_process vsftpd
                fi
            fi
        fi

        if ps | grep -v "grep" | grep -q "minidlna" && [ -f /etc/minidlna.conf ] && ! grep -q "# Modified by $SCRIPT_NAME" /etc/minidlna.conf; then
            if [ -f /jffs/configs/minidlna.conf ]; then
                cp /etc/minidlna.conf /etc/minidlna.conf.new
                cat /jffs/configs/minidlna.conf > /etc/minidlna.conf.new
            elif [ -f /jffs/configs/minidlna.conf.add ]; then
                cp /etc/minidlna.conf /etc/minidlna.conf.new
                cat /jffs/configs/minidlna.conf.add >> /etc/minidlna.conf.new
            fi

            if [ -f /etc/minidlna.conf.new ]; then
                echo "# Modified by $SCRIPT_NAME" >> /etc/minidlna.conf.new
                run_postconf_script /etc/minidlna.conf.new

                if [ "$(md5sum /etc/minidlna.conf | awk '{print $1}')" != "$(md5sum /etc/minidlna.conf.new | awk '{print $1}')" ]; then
                    cp -f /etc/minidlna.conf.new /etc/minidlna.conf

                    logger -st "$SCRIPT_TAG" "Modified /etc/minidlna.conf"

                    restart_process minidlna
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

        if ps | grep -v "grep" | grep -q "minidlna" && [ -f /etc/minidlna.conf.new ]; then
            service restart_media > /dev/null
            rm -f /etc/minidlna.conf.new
            logger -st "$SCRIPT_TAG" "Restarted media service"
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
