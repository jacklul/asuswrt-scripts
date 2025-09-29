#!/bin/sh
# Made by Jack'lul <jacklul.github.io>
#
# Modify configuration files of some selected services
#
# Implements Custom config files feature from Asuswrt-Merlin:
#  https://github.com/RMerl/asuswrt-merlin.ng/wiki/Custom-config-files
#

#jas-update=custom-configs.sh
#shellcheck disable=SC2155
#shellcheck source=./common.sh
readonly common_script="$(dirname "$0")/common.sh"
if [ -f "$common_script" ]; then . "$common_script"; else { echo "$common_script not found" >&2; exit 1; } fi

KILL_TIMEOUT=5 # how many seconds to wait before SIGKILL if the process does not stop after SIGTERM, empty or -1 means no waiting
# No RUN_EVERY_MINUTE option here as this script HAS to run every minute to check if any of the configs reverted to default

load_script_config

[ -z "$KILL_TIMEOUT" ] && KILL_TIMEOUT=-1 # empty value disables timeout
readonly FILES="/etc/profile /etc/hosts /etc/resolv.conf" # files we can modify
readonly NO_ADD_FILES="/etc/resolv.conf" # files that cannot be appended to
readonly NO_REPLACE_FILES="/etc/profile /etc/stubby/stubby.yml" # files that cannot be replaced
readonly NO_POSTCONF_FILES="/etc/profile" # files that cannot run postconf script

get_binary_location() {
    [ -z "$1" ] && { echo "Binary name not provided" >&2; exit 1; }

    _binary_name="$(echo "$1"| awk '{print $1}')"

    for _base_path in /usr/sbin /usr/bin /sbin /bin; do
        [ -f "$_base_path/$_binary_name" ] && echo "$_base_path/$_binary_name" && return
    done
}

restart_process() {
    [ -z "$1" ] && { echo "Process name not provided" >&2; exit 1; }

    _started=
    for _pid in $(/bin/ps w | grep -F "$1" | grep -v "grep\|/jffs/scripts" | awk '{print $1}'); do
        [ ! -f "/proc/$_pid/cmdline" ] && continue
        _cmdline="$(tr '\0' ' ' < "/proc/$_pid/cmdline")"

        kill -s SIGTERM "$_pid" 2> /dev/null

        _timeout="$KILL_TIMEOUT"
        while [ -f "/proc/$_pid/cmdline" ] && [ "$_timeout" -ge 0 ]; do
            sleep 1
            _timeout=$((_timeout-1))
        done

        [ -f "/proc/$_pid/cmdline" ] && kill -s SIGKILL "$_pid" 2> /dev/null

        if [ -z "$_started" ]; then
            # make sure we are executing build-in binary
            _full_binary_path=
            if [ "$(echo "$_cmdline" | cut -c 1-1)" != "/" ]; then
                _full_binary_path="$(get_binary_location "$_cmdline")"
            fi

            if [ -n "$_full_binary_path" ]; then
                _cmdline="$(echo "$_cmdline" | awk '{for (i=2; i<NF; i++) printf $i " "; print $NF}')"

                #shellcheck disable=SC2086
                "$_full_binary_path" $_cmdline && _started=1 && logecho "Restarted process: $_full_binary_path $_cmdline" alert
            else
                $_cmdline && _started=1 && logecho "Restarted process: $_cmdline" alert
            fi
        fi
    done
}

is_file_add_supported() {
    [ -z "$1" ] && { echo "File path not provided" >&2; exit 1; }
    [ -z "$NO_ADD_FILES" ] && return 0
    _new="$(echo "$1" | sed 's/\.new$//')"

    for _no_add_file in $NO_ADD_FILES; do
        [ "$_no_add_file" = "$_new" ] && return 1
    done

    return 0
}

is_file_replace_supported() {
    [ -z "$1" ] && { echo "File path not provided" >&2; exit 1; }
    [ -z "$NO_REPLACE_FILES" ] && return 0
    _new="$(echo "$1" | sed 's/\.new$//')"

    for _no_replace_file in $NO_REPLACE_FILES; do
        [ "$_no_replace_file" = "$_new" ] && return 1
    done

    return 0
}

is_file_postconf_supported() {
    [ -z "$1" ] && { echo "File path not provided" >&2; exit 1; }
    [ -z "$NO_POSTCONF_FILES" ] && return 0
    _new="$(echo "$1" | sed 's/\.new$//')"

    for _no_postconf_file in $NO_POSTCONF_FILES; do
        [ "$_no_postconf_file" = "$_new" ] && return 1
    done

    return 0
}

is_config_file_modified() {
    [ -z "$1" ] && { echo "File path not provided" >&2; exit 1; }
    [ ! -f "$1" ] && { echo "File '$1' does not exist" >&2; return 1; }
    [ ! -f "$1.new" ] && { echo "File '$1.new' does not exist" >&2; return 1; }

    if [ "$(md5sum "$1" | awk '{print $1}')" != "$(md5sum "$1.new" | awk '{print $1}')" ]; then
        return 0
    fi

    return 1
}

modify_config_file() {
    [ -z "$1" ] && { echo "File path not provided" >&2; exit 1; }
    [ ! -f "$1" ] && { echo "File '$1' does not exist" >&2; return 1; }
    # $2 = custom /jffs/configs/[NAME.conf]

    if [ -n "$2" ]; then
        _basename="$2"
    else
        _basename="$(basename "$1")"
    fi

    if [ -f "/jffs/configs/$_basename" ] && is_file_replace_supported "$1"; then
        logecho "Replacing '$1' with '/jffs/configs/$_basename'..." alert

        cat "/jffs/configs/$_basename" > "$1.new"
    elif [ -f "/jffs/configs/$_basename.add" ] && is_file_add_supported "$1"; then
        logecho "Appending '/jffs/configs/$_basename.add' to '$1'..." alert

        cp "$1" "$1.new"
        cat "/jffs/configs/$_basename.add" >> "$1.new"
    fi
}

run_postconf_script() {
    [ -z "$1" ] && { echo "File path not provided" >&2; exit 1; }
    [ ! -f "$1" ] && { echo "File '$1' does not exist" >&2; exit 1; }

    if ! is_file_postconf_supported "$1"; then
        return
    fi

    _basename="$(basename "$1" | cut -d '.' -f 1)"

    if [ -x "/jffs/scripts/$_basename.postconf" ]; then
        logecho "Running '/jffs/scripts/$_basename.postconf' script..." alert

        [ ! -f "$1.new" ] && cp "$1" "$1.new"
        sh "/jffs/scripts/$_basename.postconf" "$1.new" < /dev/null
    fi
}

add_modified_mark() {
    [ -z "$1" ] && { echo "File path not provided" >&2; exit 1; }
    [ ! -f "$1" ] && { echo "File '$1' does not exist" >&2; exit 1; }

    _basename="$(basename "$1" | cut -d '.' -f 1)"
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
    [ -z "$1" ] && { echo "File path not provided" >&2; exit 1; }
    [ ! -f "$1" ] && { echo "File '$1' does not exist" >&2; exit 1; }
    [ !  -f "$1.new" ] && { echo "File '$1.new' does not exist" >&2; exit 1; }

    cp -f "$1.new" "$1"
}

modify_files() {
    for _file in $FILES; do
        if [ -f "$_file" ] && ! grep -Fq "Modified by $script_name script" "$_file"; then
            [ ! -f "$_file.bak" ] && cp "$_file" "$_file.bak"

            modify_config_file "$_file"
            run_postconf_script "$_file"

            if [ -f "$_file.new" ]; then
                add_modified_mark "$_file.new"
                is_config_file_modified "$_file" && commit_new_file "$_file"
            fi
        fi
    done
}

restore_files() {
    for _file in $FILES; do
        if  [ -f "$_file.bak" ] && [ -f "$_file.new" ]; then
            cp -f "$_file.bak" "$_file"
            rm -f "$_file.new"
            logecho "Restored: $_file" alert
        fi
    done
}

modify_service_config_file() {
    [ -z "$1" ] && { echo "File path not provided" >&2; exit 1; }
    [ -z "$2" ] && { echo "Process name not provided" >&2; exit 1; }
    # $3 = custom /jffs/configs/[NAME.conf]

    _match="$2"
    case "$2" in
        "samba")
            _match="nmbd\|smbd"
        ;;
    esac

    if /bin/ps w | grep -v "grep" | grep -q "$_match" && [ -f "$1" ] && ! grep -Fq "Modified by $script_name script" "$1"; then
        if [ -n "$3" ]; then
            modify_config_file "$1" "$3"
        else
            modify_config_file "$1"
        fi

        run_postconf_script "$1"

        if [ -f "$1.new" ] && [ "$(md5sum "$1" | awk '{print $1}')" != "$(md5sum "$1.new" | awk '{print $1}')" ]; then
            add_modified_mark "$1.new"

            if is_config_file_modified "$1"; then
                commit_new_file "$1"

                case "$2" in
                    "avahi-daemon")
                        /usr/sbin/avahi-daemon --kill && /usr/sbin/avahi-daemon -D && logecho "Restarted process: avahi-daemon" alert
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
                        restart_process "$2"
                    ;;
                esac
            fi
        fi
    fi
}

restore_service_config_file() {
    [ -z "$1" ] && { echo "File path not provided" >&2; exit 1; }
    [ -z "$2" ] && { echo "Process/service name not provided" >&2; exit 1; }

    _match="$2"
    _service="$2"

    case "$2" in
        "mcpd")
            _service="wan"
        ;;
        "miniupnpd")
            _service="upnp"
        ;;
        "avahi-daemon")
            _service="mdns"
        ;;
        "zebra"|"ripd")
            _service="quagga"
        ;;
        "igmpproxy")
            _service="wan_line"
        ;;
        "vsftpd")
            _service="ftpd"
        ;;
        "samba")
            _match="nmbd\|smbd"
        ;;
        "minidlna")
            _service="dms"
        ;;
        "mt-daapd")
            _service="mt_daapd"
        ;;
    esac

    if /bin/ps w | grep -v "grep" | grep -q "$_match" && [ -f "$1.new" ]; then
        case "$_service" in
            "ipsec")
                service "ipsec_restart" > /dev/null
            ;;
            *)
                service "restart_${_service}" > /dev/null
            ;;
        esac

        rm -f "$1.new"

        logecho "Restarted service: $_service" alert
    fi
}

configs() {
    lockfile lockwait # not lockfail as multiple service restarts might queue this one up via service-event script

    case "$1" in
        "modify")
            # services.c
            modify_files
            modify_service_config_file "/etc/dnsmasq.conf" "dnsmasq"
            modify_service_config_file "/etc/stubby/stubby.yml" "stubby"
            # inadyn.conf - currently no way to support this as it is not running as daemon
            modify_service_config_file "/var/mcpd.conf" "mcpd"
            modify_service_config_file "/etc/upnp/config" "miniupnpd" "upnp"
            modify_service_config_file "/tmp/avahi/avahi-daemon.conf" "avahi-daemon"
            # afpd.service, adisk.service, mt-daap.service - use avahi-daemon.postconf to modify these
            modify_service_config_file "/etc/zebra.conf" "zebra"
            modify_service_config_file "/etc/ripd.conf" "ripd"
            modify_service_config_file "/tmp/torrc" "tor"

            # wan.c
            modify_service_config_file "/tmp/igmpproxy.conf" "igmpproxy"

            # snmpd.c
            modify_service_config_file "/tmp/snmpd.conf" "snmpd"

            # usb.c
            modify_service_config_file "/etc/vsftpd.conf" "vsftpd"
            modify_service_config_file "/etc/smb.conf" "samba"
            modify_service_config_file "/etc/minidlna.conf" "minidlna"
            modify_service_config_file "/etc/mt-daapd.conf" "mt-daapd"

            # vpn.c
            modify_service_config_file "/tmp/pptpd/pptpd.conf" "pptpd"

            # rc_ipsec.c
            modify_service_config_file "/etc/ipsec.conf" "ipsec"
        ;;
        "restore")
            # services.c
            restore_files
            restore_service_config_file "/etc/dnsmasq.conf" "dnsmasq"
            restore_service_config_file "/etc/stubby/stubby.yml" "stubby"
            # inadyn.conf
            restore_service_config_file "/var/mcpd.conf" "mcpd"
            restore_service_config_file "/etc/upnp/config" "miniupnpd"
            restore_service_config_file "/tmp/avahi/avahi-daemon.conf" "avahi-daemon"
            # afpd.service, adisk.service, mt-daap.service
            restore_service_config_file "/etc/zebra.conf" "zebra"
            restore_service_config_file "/etc/ripd.conf" "ripd"
            restore_service_config_file "/tmp/torrc" "tor"

            # wan.c
            restore_service_config_file "/tmp/igmpproxy.conf" "igmpproxy"

            # snmpd.c
            restore_service_config_file "/tmp/snmpd.conf" "snmpd"

            # usb.c
            restore_service_config_file "/etc/vsftpd.conf" "vsftpd"
            restore_service_config_file "/etc/smb.conf" "samba"
            restore_service_config_file "/etc/minidlna.conf" "minidlna"
            restore_service_config_file "/etc/mt-daapd.conf" "mt-daapd"

            # vpn.c
            restore_service_config_file "/tmp/pptpd/pptpd.conf" "pptpd"

            # rc_ipsec.c
            restore_service_config_file "/etc/ipsec.conf" "ipsec"
        ;;
    esac

    lockfile unlock
}

case "$1" in
    "run")
        configs modify
    ;;
    "modify")
        lockfile lockfail modify
        modify_config_file "$2"
        run_postconf_script "$2"
        add_modified_mark "$2.new"
        commit_new_file "$2"
        lockfile unlock modify
    ;;
    "start")
        crontab_entry add "*/1 * * * * $script_path run"
        configs modify
    ;;
    "stop")
        crontab_entry delete
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
