#!/bin/sh
# Made by Jack'lul <jacklul.github.io>
#
# This file contains common stuff used by the scripts
#

#jas-update=common.sh
#shellcheck disable=SC2155

# Make sure this file is not included multiple times
[ -n "$JAS_COMMON" ] && return
readonly JAS_COMMON=1

# Prevent direct execution
[ "$(basename "$0")" = "common.sh" ] && { echo "This file is not meant to be executed directly"; exit 1; }

# Force a safer umask
umask 022

# Static shared variables
if [ -z "$script_path" ]; then # sourced from a script
    readonly script_path="$(readlink -f "$0")"
    readonly script_dir="$(dirname "$script_path")"
    readonly script_name="$(basename "$script_path" .sh)"
    #shellcheck disable=SC2034
    readonly script_config="$script_dir/$script_name.conf"
    readonly common_config="$script_dir/common.conf"
    readonly SCRIPTS_DIR="$script_dir"
elif [ -n "$SCRIPTS_DIR" ]; then # inherited from jas.sh
    readonly common_config="$SCRIPTS_DIR/common.conf"
else
    echo "Cannot locate scripts directory!"
    exit 1
fi

####################

# Shared configuration variables
TMP_DIR=/tmp/jas # used by the scripts to store temporary data
NO_COLORS=false # set to true to disable ANSI colors
NO_LOGGER=false # disable messages sent via logger command
CAPTURE_STDOUT=false # set to true to enable logging of stdout when not running interactively
CAPTURE_STDERR=false # set to true to enable logging of stderr when not running interactively
REMOVE_OPT_FROM_PATH=false # set to true to remove /opt paths from PATH temporarily while running
RENAMED_SCRIPTS_SUPPORT=false # set to true to enable support for renamed scripts

# Migrate old config.conf to new name if it exists
if [ -f "$SCRIPTS_DIR/config.conf" ] && [ ! -f "$common_config" ]; then
    mv "$SCRIPTS_DIR/config.conf" "$common_config"
fi

#shellcheck disable=SC1090
[ -n "$common_config" ] && [ -f "$common_config" ] && . "$common_config"

# Mark these as immutable
readonly TMP_DIR NO_COLORS NO_LOGGER CAPTURE_STDOUT CAPTURE_STDERR REMOVE_OPT_FROM_PATH RENAMED_SCRIPTS_SUPPORT

####################

[ -t 0 ] && console_is_interactive=true

#shellcheck disable=SC2174
[ ! -d "$TMP_DIR" ] && mkdir -pm 755 "$TMP_DIR"

if [ -z "$console_is_interactive" ]; then
    if [ "$CAPTURE_STDOUT" = true ]; then
        exec 1>> "$TMP_DIR/$script_name-stdout.log"
    fi

    if [ "$CAPTURE_STDERR" = true ]; then
        exec 2>> "$TMP_DIR/$script_name-stderr.log"
    fi
fi

if [ "$REMOVE_OPT_FROM_PATH" = true ]; then
    export PATH="$(echo "$PATH" | sed 's|:/opt[^:]*||g; s|^/opt[^:]*:||; s|^/opt[^:]*$||')"
fi

trap trapexit EXIT HUP INT QUIT TERM

####################

# ANSI colors
#shellcheck disable=SC2034
if [ "$NO_COLORS" != true ]; then
    fbk="[1;30m"
    frd="[1;31m"
    fgn="[1;32m"
    fyw="[1;33m"
    fbe="[1;34m"
    fpe="[1;35m"
    fcn="[1;36m"
    fwe="[1;37m"
    frt="[0m"
fi

####################

# Do not define any variables before this definition without whitespace
# before it, otherwise 'jas.sh config common' will pick it up
load_script_config() {
    #shellcheck disable=SC1090
    [ -f "$script_config" ] && . "$script_config"
}

logecho() { # $2 = force logging to syslog even if interactive
    [ -z "$1" ] && return 1

    if [ "$NO_LOGGER" != true ] && { [ -z "$console_is_interactive" ] || [ -n "$2" ] ; }; then
        logger -t "$script_name" "$1"
    fi

    echo "$1"
}

is_merlin_firmware() {
    [ -z "$merlin_uname_check" ] && merlin_uname_check="$(uname -o)" # cache in case of multiple calls

    if [ "$merlin_uname_check" = "ASUSWRT-Merlin" ]; then
        return 0
    fi

    return 1
}

is_started_by_system() {
    [ -n "$JAS_BOOT" ] && return 0
    _ppid=$PPID
    [ "$_ppid" -eq 1 ] && return 0

    while true; do
        [ -z "$_ppid" ] && break
        [ "$_ppid" -le 1 ] && break
        [ ! -d "/proc/$_ppid" ] && break
        grep -Fq "cron" "/proc/$_ppid/comm" && return 0
        grep -Fq "hotplug" "/proc/$_ppid/comm" && return 0
        _ppid=$(< "/proc/$_ppid/stat" awk '{print $4}')
    done

    return 1
}

lockfile() {
    [ -z "$script_name" ] && script_name="$(basename "$0" .sh)"
    _lockfile="/var/lock/jas-$script_name.lock"
    [ -n "$2" ] && _lockfile="/var/lock/jas-$script_name-$2.lock"
    [ -f "$_lockfile" ] && lockpid="$(cat "$_lockfile")"

    case "$1" in
        "lockwait"|"lockfail"|"lockexit")
            if [ -n "$lockfd" ]; then
                logecho "Lockfile is already locked by this process ($_lockfile)"
                exit 1
            fi

            for _fd_test in "/proc/$$/fd"/*; do
                if [ "$(readlink -f "$_fd_test")" = "$_lockfile" ]; then
                    logecho "File descriptor ($(basename "$_fd_test")) is already open for the same lockfile ($_lockfile)"
                    exit 1
                fi
            done

            _fd=$(lockfile_fd)
            eval exec "$_fd>$_lockfile"

            case "$1" in
                "lockwait")
                    _lockwait=60
                    while ! flock -nx "$_fd"; do
                        eval exec "$_fd>&-"
                        _lockwait=$((_lockwait-1))

                        if [ "$_lockwait" -lt 0 ]; then
                            logecho "Failed to acquire a lock after 60 seconds ($_lockfile)"
                            exit 1
                        fi

                        sleep 1
                        _fd=$(lockfile_fd)
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

            echo $$ > "$_lockfile"
            chmod 644 "$_lockfile"
            lockfd="$_fd"
        ;;
        "unlock")
            [ -z "$lockfd" ] && return 1
            flock -u "$lockfd"
            eval exec "$lockfd>&-"
            lockfd=
            rm -f "$_lockfile"
        ;;
        "check")
            [ -n "$lockpid" ] && [ -f "/proc/$lockpid/stat" ] && return 0
            return 1
        ;;
        "kill")
            [ -n "$lockpid" ] && [ -f "/proc/$lockpid/stat" ] && kill -9 "$lockpid" && return 0
            return 1
        ;;
    esac
}

lockfile_fd() {
    _lfd_min=100
    _lfd_max=200

    while [ -f "/proc/$$/fd/$_lfd_min" ]; do
        _lfd_min=$((_lfd_min+1))
        [ "$_lfd_min" -gt "$_lfd_max" ] && { logecho "Error: No free file descriptors available"; exit 1; }
    done

    echo "$_lfd_min"
}

trapexit() {
    code=$?
    type script_trapexit > /dev/null 2>&1 && script_trapexit
    [ -n "$lockfd" ] && lockfile unlock
    exit $code
}

crontab_entry() {
    _action="$1"
    _name="$2"

    if [ "$_action" = "add" ]; then
        _data="$2"
        _name="$3"
        _no_cron_queue="$4"
    fi

    [ -z "$_name" ] && _name="$script_name"
    _name="jas-$_name"

    _cron_queue="$(resolve_script_basename "cron-queue.sh")"
    [ ! -x "$_cron_queue" ] && _cron_queue=""

    case "$_action" in
        "add")
            if [ -n "$_cron_queue" ] && echo "$_data" | grep -Fq "*/1 * * * *"; then
                sh "$_cron_queue" add "$_name" "$(echo "$_data" | sed 's#\*/1 \* \* \* \* ##')"
                return 0
            fi

            cru a "$_name" "$_data"
        ;;
        "delete")
            [ -n "$_cron_queue" ] && sh "$_cron_queue" delete "$_name"
            cru d "$_name"
        ;;
        "check")
            if [ -n "$_cron_queue" ]; then
                if sh "$_cron_queue" check "$_name"; then
                    return 0
                fi
            fi

            if cru l | grep -Fq "#$_name#"; then
                return 0
            fi

            return 1
        ;;
        "list")
            if [ -n "$_cron_queue" ]; then
                sh "$_cron_queue" list | awk 'NF {print "*/1 * * * * " $0}'
            fi

            cru l
        ;;
        *)
            echo "Invalid action: $_action"
            return 1
        ;;
    esac

    return 0
}

# these two sed_* functions are based on https://github.com/RMerl/asuswrt-merlin.ng/blob/master/release/src/router/others/helper.sh
sed_quote() {
    printf "%s\n" "$1" | sed 's/[]\/$*.^&[]/\\&/g'
}

sed_helper() {
    _pattern=$(sed_quote "$2")
    _content=$(sed_quote "$3")
    _file="$4"

    case "$1" in
        "replace")
            sed "s/$_pattern/$_content/" -i "$_file"
        ;;
        "prepend")
            sed "/$_pattern/i$_content" -i "$_file"
        ;;
        "append")
            sed "/$_pattern/a$_content" -i "$_file"
        ;;
        "delete")
            if [ -z "$_file" ] && [ -n "$3" ]; then
                _file="$3"
            fi

            sed "/$_pattern/d" -i "$_file"
        ;;
        *)
            echo "Invalid mode: $1"
            return 1
        ;;
    esac
}

get_curl_binary() {
    if [ -f /opt/bin/curl ]; then
        _curl_binary="/opt/bin/curl" # prefer Entware's curl
    elif [ -f /usr/bin/curl ]; then
        _curl_binary="/usr/bin/curl"
    elif type curl > /dev/null 2>&1; then
        _curl_binary="curl"
    else
        return 1
    fi

    echo "$_curl_binary"
}

#shellcheck disable=SC2086
fetch() {
    [ -z "$1" ] && { echo "No URL specified"; return 1; }

    _url="$1"
    _output="$2"
    _timeout="$3"

    if [ -z "$curl_binary" ] && type get_curl_binary > /dev/null 2>&1; then
        curl_binary="$(get_curl_binary)"
    fi

    if [ -n "$curl_binary" ]; then
        [ -n "$_timeout" ] && _timeout="-m $_timeout"

        if [ -n "$_output" ]; then
            $curl_binary -fsSL "$_url" -o "$_output" $_timeout
            return $?
        else
            $curl_binary -sfL --head "$_url" $_timeout > /dev/null
            return $?
        fi
    elif type wget > /dev/null 2>&1; then
        [ -n "$_timeout" ] && _timeout="--timeout=$_timeout"

        if [ -n "$_output" ]; then
            wget -q "$_url" -O "$_output" $_timeout
            return $?
        else
            wget -q --spider "$_url" -O /dev/null $_timeout
            return $?
        fi
    else
        echo "curl or wget not found"
        return 1
    fi
}

get_script_basename() {
    { [ -z "$1" ] || [ ! -f "$1" ] ; } && return 1

    _basename="$(basename "$1")"
    _new_basename="$(grep -E '^#(\s+)?jas-update=' "$1" | sed 's/.*jas-update=//' | sed 's/[[:space:]]*$//')"

    if [ -n "$_new_basename" ]; then
        echo "$_new_basename"
    else
        echo "$_basename"
    fi
}

resolve_script_basename() {
    _name="$(basename "$1")"
    [ -z "$_name" ] && return 1

    if [ -f "$SCRIPTS_DIR/$_name" ]; then
        echo "$SCRIPTS_DIR/$_name"
        return
    fi

    if [ "$RENAMED_SCRIPTS_SUPPORT" != true ]; then
        return 1
    fi

    # Read from cache if available
    if [ -n "$script_basename_cache" ] && echo "$script_basename_cache" | grep -Fq " $_name="; then
        for _entry in $script_basename_cache; do
            _path="$(echo "$_entry" | cut -d '=' -f 2)"
            _entry="$(echo "$_entry" | cut -d '=' -f 1)"

            if [ "$_entry" = "$_name" ]; then
                echo "$_path"
                return
            fi
        done
    fi

    if [ -z "$script_basename_cache" ]; then # generate cache only once
        # In case user renamed the script, we need to rescan all scripts and read jas-update tags
        for _entry in "$SCRIPTS_DIR"/*.sh; do
            _entry="$(readlink -f "$_entry")"
            ! grep -Fq "jas-update=" "$_entry" && continue # skip scripts without the tag

            _entry_name="$(get_script_basename "$_entry")"

            script_basename_cache="$(echo "$script_basename_cache" | sed "s/ $_entry_name=[^ ]*//g")"
            script_basename_cache="$script_basename_cache $_entry_name=$_entry"

            if [ "$_entry_name" = "$_name" ]; then
                _found_entry="$_entry"
            fi
        done

        [ -n "$_found_entry" ] && { echo "$_found_entry"; return; }
    fi

    return 1
}

execute_script_basename() {
    _script="$(resolve_script_basename "$1")"

    if [ -n "$_script" ] && [ -x "$_script" ]; then
        [ "$2" = "check" ] && return 0
        shift
        $_script "$@"
        return $?
    fi

    return 1
}

interface_exists() {
    [ -z "$1" ] && return 1
    _iface="$1"

    if [ "$(printf "%s" "$_iface" | tail -c 1)" = "*" ]; then
        _iface="${_iface%?}"

        if ip link show | grep -Fq ": $_iface"; then
            return 0
        fi
    elif ip link show "$_iface" >/dev/null 2>&1; then
        return 0
    fi

    return 1
}

get_wan_interface() {
    _id="$1"
    [ -z "$_id" ] && _id=0

    _interface="$(nvram get "wan${_id}_ifname")"

    _test="$(nvram get "wan${_id}_gw_ifname")"
    if [ "$_test" != "$_interface" ]; then
        _interface="$_test"
    fi

    echo "$_interface"
}

mask_to_cidr() {
    [ -z "$1" ] && return 1
    _mask="$1"
    _cidr=0
    _oldIFS=$IFS
    IFS='.'
    for _octet in $_mask; do
        case $_octet in
            255) _cidr=$((_cidr + 8)) ;;
            254) _cidr=$((_cidr + 7)) ;;
            252) _cidr=$((_cidr + 6)) ;;
            248) _cidr=$((_cidr + 5)) ;;
            240) _cidr=$((_cidr + 4)) ;;
            224) _cidr=$((_cidr + 3)) ;;
            192) _cidr=$((_cidr + 2)) ;;
            128) _cidr=$((_cidr + 1)) ;;
            0) ;;
            *) echo "Invalid subnet mask octet: $_octet"; return 1 ;;
        esac
    done
    IFS=$_oldIFS
    echo "$_cidr"
}

#shellcheck disable=SC2086
calculate_network() {
    { [ -z "$1" ] || [ -z "$2" ] ; } && return 1
    _ip="$1"
    _mask="$2"
    _oldIFS=$IFS
    IFS='.'
    set -- $_ip
    _ip1=$1; _ip2=$2; _ip3=$3; _ip4=$4
    set -- $_mask
    _mask1=$1; _mask2=$2; _mask3=$3; _mask4=$4
    IFS=$_oldIFS
    _net1=$((_ip1 & _mask1))
    _net2=$((_ip2 & _mask2))
    _net3=$((_ip3 & _mask3))
    _net4=$((_ip4 & _mask4))
    echo "$_net1.$_net2.$_net3.$_net4"
}

get_vpnc_clientlist() {
    [ -z "$vpnc_clientlist" ] && vpnc_clientlist="$(nvram get vpnc_clientlist | tr '<' '\n')"
    echo "$vpnc_clientlist"
}
