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

readonly script_path="$(readlink -f "$0")"
readonly script_name="$(basename "$script_path" .sh)"
readonly script_dir="$(dirname "$script_path")"

readonly ETC_FILES="profile hosts" # /etc files we can modify
readonly NOREPLACE_FILES="/etc/profile /etc/stubby/stubby.yml" # files that cannot be replaced
readonly NOPOSTCONF_FILES="/etc/profile" # files that cannot run postconf script

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
            if [ -n "$_lockpid" ] && ! grep -q "$script_name" "/proc/$_lockpid/cmdline" 2> /dev/null; then
                _lockpid=
            fi

            case "$1" in
                "lockfail"|"lockexit")
                    if [ -n "$_lockpid" ] && [ -f "/proc/$_lockpid/stat" ]; then
                        [ "$1" = "lockfail" ] && return 1
                        exit 1
                    fi
                ;;
            esac

            while [ -f "/proc/$$/fd/$_fd" ]; do
                _fd=$((_fd+1))

                [ "$_fd" -gt "$_fd_max" ] && { echo "Failed to acquire a lock - no available file descriptor"; exit 1; }
            done

            eval exec "$_fd>$_lockfile"

            case "$1" in
                "lockwait")
                    _lockwait=0
                    while ! flock -nx "$_fd" && { [ -z "$_lockpid" ] || [ -f "/proc/$_lockpid/stat" ] ; }; do #flock -x "$_fd"
                        sleep 1
                        if [ "$_lockwait" -ge 60 ]; then
                            echo "Failed to acquire a lock after 60 seconds"
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
            trap 'flock -u $_fd; rm -f "$_lockfile" "$_pidfile"; exit $?' INT TERM EXIT
        ;;
        "unlock")
            flock -u "$_fd"
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

get_binary_location() {
    [ -z "$1" ] && { echo "Binary name not provided"; exit 1; }

    _binary_name="$(echo "$1"| awk '{print $1}')"

    for _base_path in /usr/sbin /usr/bin /sbin /bin; do
        [ -f "$_base_path/$_binary_name" ] && echo "$_base_path/$_binary_name" && return
    done
}

restart_process() {
    [ -z "$1" ] && { echo "Process name not provided"; exit 1; }

    _started=
    for _pid in $(/bin/ps w | grep "$1" | grep -v "grep\|/jffs/scripts" | awk '{print $1}'); do
        [ ! -f "/proc/$_pid/cmdline" ] && continue
        _cmdline="$(tr "\0" " " < "/proc/$_pid/cmdline")"

        killall "$1"
        [ -f "/proc/$_pid/cmdline" ] && kill -s SIGTERM "$_pid" 2> /dev/null
        [ -f "/proc/$_pid/cmdline" ] && kill -s SIGKILL "$_pid" 2> /dev/null

        if [ -z "$_started" ]; then
            # make sure we are executing build-in binary
            _full_binary_path=
            if [ "$(echo "$_cmdline" | cut -c1-1)" != "/" ]; then
                _full_binary_path="$(get_binary_location "$_cmdline")"
            fi

            if [ -n "$_full_binary_path" ]; then
                _cmdline="$(echo "$_cmdline" | awk '{for (i=2; i<NF; i++) printf $i " "; print $NF}')"

                #shellcheck disable=SC2086
                "$_full_binary_path" $_cmdline && _started=1 && logger -st "$script_name" "Restarted process: $_full_binary_path $_cmdline"
            else
                $_cmdline && _started=1 && logger -st "$script_name" "Restarted process: $_cmdline"
            fi
        fi
    done
}

is_file_replace_supported() {
    [ -z "$1" ] && { echo "File path not provided"; exit 1; }

    for _file in $NOREPLACE_FILES; do
        [ "$_file" = "$(echo "$1" | sed 's/\.new$//')" ] && return 1
    done

    return 0
}

is_file_postconf_supported() {
    [ -z "$1" ] && { echo "File path not provided"; exit 1; }

    for _file in $NOPOSTCONF_FILES; do
        [ "$_file" = "$1" ] && return 1
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
        _basename="$2"
    else
        _basename="$(basename "$1")"
    fi

    if [ -f "/jffs/configs/$_basename" ] && is_file_replace_supported "$1"; then
        logger -st "$script_name" "Replacing '$1' with '/jffs/configs/$_basename'..."

        cat "/jffs/configs/$_basename" > "$1.new"
    elif [ -f "/jffs/configs/$_basename.add" ]; then
        logger -st "$script_name" "Appending '/jffs/configs/$_basename.add' to '$1'..."

        cp "$1" "$1.new"
        cat "/jffs/configs/$_basename.add" >> "$1.new"
    fi
}

run_postconf_script() {
    [ -z "$1" ] && { echo "File path not provided"; exit 1; }

    if ! is_file_postconf_supported "$1"; then
        return
    fi

    _basename="$(basename "$1" | cut -d. -f1)"

    if [ -x "/jffs/scripts/$_basename.postconf" ]; then
        logger -st "$script_name" "Running '/jffs/scripts/$_basename.postconf' script..."

        [ ! -f "$1.new" ] && cp "$1" "$1.new"
        sh "/jffs/scripts/$_basename.postconf" "$1.new"
    fi
}

add_modified_mark() {
    [ -z "$1" ] && { echo "File path not provided"; exit 1; }

    _basename="$(basename "$1" | cut -d. -f1)"
    _comment="#"

    case "$_basename" in
        "zebra")
            _comment="!"
        ;;
    esac

    echo "" >> "$1"
    echo "$_comment Modified by $script_name script" >> "$1"
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

    if /bin/ps w | grep -v "grep" | grep -q "$2" && [ -f "$1" ] && ! grep -q "Modified by $script_name script" "$1"; then
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
                        /usr/sbin/avahi-daemon --kill && /usr/sbin/avahi-daemon -D && logger -st "$script_name" "Restarted process: avahi-daemon"
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

    if /bin/ps w | grep -v "grep" | grep -q "$2" && [ -f "$1.new" ]; then
        case "$3" in
            "ipsec")
                service "ipsec_restart" > /dev/null
            ;;
            *)
                service "restart_$3" > /dev/null
            ;;
        esac

        rm -f "$1.new"

        logger -st "$script_name" "Restarted service: $3"
    fi
}

modify_etc_files() {
    for _file in $ETC_FILES; do
        if [ -f "/etc/$_file" ] && ! grep -q "Modified by $script_name script" "/etc/$_file"; then
            [ ! -f "/etc/$_file.bak" ] && cp "/etc/$_file" "/etc/$_file.bak"

            modify_config_file "/etc/$_file"

            if [ -f "/etc/$_file.new" ]; then
                add_modified_mark "/etc/$_file.new"
                is_config_file_modified "/etc/$_file" && commit_new_file "/etc/$_file"
            fi
        fi
    done
}

restore_etc_files() {
    for _file in $ETC_FILES; do
        if  [ -f "/etc/$_file.bak" ] && [ -f "/etc/$_file.new" ]; then
            cp -f "/etc/$_file.bak" "/etc/$_file"
            rm -f "/etc/$_file.new"
            logger -st "$script_name" "Restored: /etc/$_file"
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
        if { [ ! -x "$script_dir/cron-queue.sh" ] || ! "$script_dir/cron-queue.sh" check "$script_name" ; } && ! cru l | grep -q "#$script_name#"; then
            exit # do not run if not started
        fi

        configs modify
    ;;
    "start")
        if [ -x "$script_dir/cron-queue.sh" ]; then
            sh "$script_dir/cron-queue.sh" add "$script_name" "$script_path run"
        else
            cru a "$script_name" "*/1 * * * * $script_path run"
        fi

        sh "$script_path" run
    ;;
    "stop")
        [ -x "$script_dir/cron-queue.sh" ] && sh "$script_dir/cron-queue.sh" remove "$script_name"
        cru d "$script_name"

        configs restore
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
