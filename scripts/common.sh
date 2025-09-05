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

# Force a safer umask
umask 022

# Static shared variables
if [ -z "$script_path" ]; then # sourced from a script
    readonly script_path="$(readlink -f "$0")"
    readonly script_dir="$(dirname "$script_path")"
    readonly script_name="$(basename "$script_path" .sh)"
    #shellcheck disable=SC2034
    readonly script_config="$script_dir/$script_name.conf"
    readonly common_config="$script_dir/config.conf"
    readonly SCRIPTS_DIR="$script_dir"
elif [ -n "$SCRIPTS_DIR" ]; then # inherited from jas.sh
    readonly common_config="$SCRIPTS_DIR/config.conf"
else
    echo "Cannot locate scripts directory!"
    exit 1
fi

####################

# Shared configuration variables
TMP_DIR=/tmp/jas # used by the scripts to store temporary data
NO_COLORS=false # set to true to disable ANSI colors
EXCLUDE_OPT_FROM_PATH=false # set to true to exclude /opt paths from PATH

#shellcheck disable=SC1090
[ -n "$common_config" ] && [ -f "$common_config" ] && . "$common_config"

# Mark these as immutable
readonly TMP_DIR NO_COLORS EXCLUDE_OPT_FROM_PATH

#shellcheck disable=SC2174
[ ! -d "$TMP_DIR" ] && mkdir -pm 755 "$TMP_DIR"

if [ "$EXCLUDE_OPT_FROM_PATH" = true ]; then
    export PATH="$(echo "$PATH" | sed 's|:/opt[^:]*||g; s|^/opt[^:]*:||; s|^/opt[^:]*$||')"
fi

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

load_script_config() {
    #shellcheck disable=SC1090
    [ -f "$script_config" ] && . "$script_config"
}

is_merlin_firmware() {
    if [ -f /usr/sbin/helper.sh ]; then
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
    _pidfile="/var/run/jas-$script_name.pid"
    _fd_min=100
    _fd_max=200

    if [ -n "$2" ]; then
        _lockfile="/var/lock/jas-$script_name-$2.lock"
        _pidfile="/var/run/jas-$script_name-$2.lock"
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
                    _lockwait=60
                    while ! flock -nx "$_fd"; do
                        eval exec "$_fd>&-"
                        _lockwait=$((_lockwait-1))

                        if [ "$_lockwait" -lt 0 ]; then
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

            #shellcheck disable=SC2154
            trap 'code=$?; flock -u $_fd; rm -f "$_lockfile" "$_pidfile"; exit $code' INT TERM QUIT EXIT
        ;;
        "unlock")
            flock -u "$_fd"
            eval exec "$_fd>&-"
            rm -f "$_lockfile" "$_pidfile"
            trap - INT TERM QUIT EXIT
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
}

crontab_entry() {
    _action="$1"
    _name="$2"

    if [ "$_action" = "add" ]; then
        _data="$2"
        _name="$3"
        _no_cron_queue="$4"
    fi

    [ -z "$_name" ] && _name="${script_name}"
    _name="jas-$_name"

    if [ -z "$_no_cron_queue" ]; then # for cron-queue script - avoid adding entry to itself
        _cron_queue="$(resolve_script_basename "cron-queue.sh")"
        [ ! -x "$_cron_queue" ] && _cron_queue=""
    fi

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
    [ ! -f "$1" ] && return

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

    if [ -f "$SCRIPTS_DIR/$_name" ]; then
        echo "$SCRIPTS_DIR/$_name"
        return
    fi

    # Read from cache if available
    if [ -n "$script_basename_cache" ] && echo "$script_basename_cache" | grep -Fq " $_name="; then
        for _entry in $script_basename_cache; do
            _path="$(echo "$_entry" | cut -d'=' -f2)"
            _entry="$(echo "$_entry" | cut -d'=' -f1)"

            if [ "$_entry" = "$_name" ]; then
                echo "$_path"
                return
            fi
        done
    fi

    # In case user renamed the script, we need to rescan all scripts and read jas-update tags
    for _entry in "$SCRIPTS_DIR"/*.sh; do
        _entry="$(readlink -f "$_entry")"
        ! grep -Fq "jas-update=" "$_entry" && continue # skip scripts without the tag

        _entry_name="$(get_script_basename "$_entry")"

        script_basename_cache="$(echo "$script_basename_cache" | sed "s/ $_entry_name=[^ ]*//g")"
        script_basename_cache="$script_basename_cache $_entry_name=$_entry"

        if [ "$_entry_name" = "$_name" ]; then
            echo "$_entry"
            return
        fi
    done

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
