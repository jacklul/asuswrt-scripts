#!/bin/sh
# Made by Jack'lul <jacklul.github.io>
#
# Install and enable Entware
#
# Based on:
#  https://bin.entware.net/armv7sf-k3.2/installer/generic.sh
#  https://raw.githubusercontent.com/RMerl/asuswrt-merlin.ng/a46283c8cbf2cdd62d8bda231c7a79f5a2d3b889/release/src/router/others/entware-setup.sh
#

#jacklul-asuswrt-scripts-update=entware.sh
#shellcheck disable=SC2155,SC2016

readonly script_path="$(readlink -f "$0")"
readonly script_name="$(basename "$script_path" .sh)"
readonly script_dir="$(dirname "$script_path")"
readonly script_config="$script_dir/$script_name.conf"

IN_RAM="" # Install Entware and packages in RAM (/tmp), space separated list
ARCHITECTURE="" # Entware architecture, set it only when auto install (to /tmp) can't detect it properly
ALTERNATIVE=false # Perform alternative install (separated users from the system)
USE_HTTPS=false # retrieve files using HTTPS, applies to OPKG repository and installation downloads
BASE_URL="bin.entware.net" # Base Entware URL, can be changed if you wish to use a different mirror (no http/https prefix and no ending slash!)
WAIT_LIMIT=60 # how many minutes to wait for auto install before giving up (in RAM only)
CACHE_FILE="/tmp/last_entware_device" # where to store last device Entware was mounted on
INSTALL_LOG="/tmp/entware-install.log" # where to store installation log (in RAM only)
REQUIRE_NTP=true # require time to be synchronized to start

if [ -f "$script_config" ]; then
    #shellcheck disable=SC1090
    . "$script_config"
fi

default_base_url="bin.entware.net" # hardcoded in opkg.conf
last_entware_device=""
[ -f "$CACHE_FILE" ] && last_entware_device="$(cat "$CACHE_FILE")"
check_url="http://$BASE_URL"
[ "$USE_HTTPS" = true ] && check_url="$(echo "$check_url" | sed 's/http:/https:/')"
curl_binary="curl"
#[ -f /opt/bin/curl ] && curl_binary="/opt/bin/curl" # what was I thinking here?

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
            while [ -f "/proc/$$/fd/$_fd" ]; do
                _fd=$((_fd+1))
                [ "$_fd" -gt "$_fd_max" ] && { logger -st "$script_name" "No free file descriptors available"; exit 1; }
            done

            eval exec "$_fd>$_lockfile"

            case "$1" in
                "lockwait")
                    _lockwait=0
                    while ! flock -nx "$_fd"; do # flock -x "$_fd" sometimes gets stuck
                        sleep 1
                        if [ "$_lockwait" -ge 60 ]; then
                            logger -st "$script_name" "Failed to acquire a lock after 60 seconds"
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
} #LOCKFILE_END#

is_started_by_system() { #ISSTARTEDBYSYSTEM_START#
    _ppid=$PPID
    while true; do
        [ -z "$_ppid" ] && break
        _ppid=$(< "/proc/$_ppid/stat" awk '{print $4}')
        grep -Fq "cron" "/proc/$_ppid/comm" && return 0
        grep -Fq "hotplug" "/proc/$_ppid/comm" && return 0
        [ "$_ppid" -gt 1 ] || break
    done
    return 1
} #ISSTARTEDBYSYSTEM_END#

# could also be [ "$(uname -o)" = "ASUSWRT-Merlin" ] or [ -f "/www/images/merlin-logo.png" ] ?
is_merlin_firmware() { #ISMERLINFIRMWARE_START#
    if [ -f "/usr/sbin/helper.sh" ]; then
        return 0
    fi
    return 1
} #ISMERLINFIRMWARE_END#

lockfile_extended() { #LOCKFILE_START#
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
            if [ -n "$_lockpid" ] && ! grep -Fq "$script_name" "/proc/$_lockpid/cmdline" 2> /dev/null; then
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
                [ "$_fd" -gt "$_fd_max" ] && { logger -st "$script_name" "Failed to acquire a lock - no free file descriptors available"; exit 1; }
            done

            eval exec "$_fd>$_lockfile"

            case "$1" in
                "lockwait")
                    _lockwait=0
                    while ! flock -nx "$_fd" && { [ -z "$_lockpid" ] || [ -f "/proc/$_lockpid/stat" ] ; }; do #flock -x "$_fd"
                        sleep 1
                        if [ "$_lockwait" -ge 90 ]; then
                            logger -st "$script_name" "Failed to acquire a lock after waiting 90 seconds"
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
} #LOCKFILE_END#

is_started_by_system() { #ISSTARTEDBYSYSTEM_START#
    _ppid=$PPID
    while true; do
        [ -z "$_ppid" ] && break
        _ppid=$(< "/proc/$_ppid/stat" awk '{print $4}')
        grep -Fq "cron" "/proc/$_ppid/comm" && return 0
        grep -Fq "hotplug" "/proc/$_ppid/comm" && return 0
        [ "$_ppid" -gt 1 ] || break
    done
    return 1
} #ISSTARTEDBYSYSTEM_END#

# could also be [ "$(uname -o)" = "ASUSWRT-Merlin" ] or [ -f "/www/images/merlin-logo.png" ] ?
is_merlin_firmware() { #ISMERLINFIRMWARE_START#
    if [ -f "/usr/sbin/helper.sh" ]; then
        return 0
    fi
    return 1
} #ISMERLINFIRMWARE_END#

lockfile2() { #LOCKFILE_START#
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
            if [ -n "$_lockpid" ] && ! grep -Fq "$script_name" "/proc/$_lockpid/cmdline" 2> /dev/null; then
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

                [ "$_fd" -gt "$_fd_max" ] && { logger -st "$script_name" "Failed to acquire a lock - no free file descriptors available"; exit 1; }
            done

            eval exec "$_fd>$_lockfile"

            case "$1" in
                "lockwait")
                    _lockwait=0
                    while ! flock -nx "$_fd" && { [ -z "$_lockpid" ] || [ -f "/proc/$_lockpid/stat" ] ; }; do #flock -x "$_fd"
                        sleep 1
                        if [ "$_lockwait" -ge 90 ]; then
                            logger -st "$script_name" "Failed to acquire a lock after waiting 90 seconds"
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
} #LOCKFILE_END#

is_started_by_system() { #ISSTARTEDBYSYSTEM_START#
    _ppid=$PPID
    while true; do
        [ -z "$_ppid" ] && break
        _ppid=$(< "/proc/$_ppid/stat" awk '{print $4}')
        grep -Fq "cron" "/proc/$_ppid/comm" && return 0
        grep -Fq "hotplug" "/proc/$_ppid/comm" && return 0
        [ "$_ppid" -gt 1 ] || break
    done
    return 1
} #ISSTARTEDBYSYSTEM_END#

# could also be [ "$(uname -o)" = "ASUSWRT-Merlin" ] or [ -f "/www/images/merlin-logo.png" ] ?
is_merlin_firmware() { #ISMERLINFIRMWARE_START#
    if [ -f "/usr/sbin/helper.sh" ]; then
        return 0
    fi
    return 1
} #ISMERLINFIRMWARE_END#

lockfile2() { #LOCKFILE_START#
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
            if [ -n "$_lockpid" ] && ! grep -Fq "$script_name" "/proc/$_lockpid/cmdline" 2> /dev/null; then
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

                [ "$_fd" -gt "$_fd_max" ] && { logger -st "$script_name" "Failed to acquire a lock - no free file descriptors available"; exit 1; }
            done

            eval exec "$_fd>$_lockfile"

            case "$1" in
                "lockwait")
                    _lockwait=0
                    while ! flock -nx "$_fd" && { [ -z "$_lockpid" ] || [ -f "/proc/$_lockpid/stat" ] ; }; do #flock -x "$_fd"
                        sleep 1
                        if [ "$_lockwait" -ge 90 ]; then
                            logger -st "$script_name" "Failed to acquire a lock after waiting 90 seconds"
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
} #LOCKFILE_END#

is_started_by_system() { #ISSTARTEDBYSYSTEM_START#
    _ppid=$PPID
    while true; do
        [ -z "$_ppid" ] && break
        _ppid=$(< "/proc/$_ppid/stat" awk '{print $4}')
        grep -Fq "cron" "/proc/$_ppid/comm" && return 0
        grep -Fq "hotplug" "/proc/$_ppid/comm" && return 0
        [ "$_ppid" -gt 1 ] || break
    done
    return 1
} #ISSTARTEDBYSYSTEM_END#

# could also be [ "$(uname -o)" = "ASUSWRT-Merlin" ] or [ -f "/www/images/merlin-logo.png" ] ?
is_merlin_firmware() { #ISMERLINFIRMWARE_START#
    if [ -f "/usr/sbin/helper.sh" ]; then
        return 0
    fi
    return 1
} #ISMERLINFIRMWARE_END#

lockfile2() { #LOCKFILE_START#
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
            if [ -n "$_lockpid" ] && ! grep -Fq "$script_name" "/proc/$_lockpid/cmdline" 2> /dev/null; then
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

                [ "$_fd" -gt "$_fd_max" ] && { logger -st "$script_name" "Failed to acquire a lock - no free file descriptors available"; exit 1; }
            done

            eval exec "$_fd>$_lockfile"

            case "$1" in
                "lockwait")
                    _lockwait=0
                    while ! flock -nx "$_fd" && { [ -z "$_lockpid" ] || [ -f "/proc/$_lockpid/stat" ] ; }; do #flock -x "$_fd"
                        sleep 1
                        if [ "$_lockwait" -ge 90 ]; then
                            logger -st "$script_name" "Failed to acquire a lock after waiting 90 seconds"
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
} #LOCKFILE_END#

is_started_by_system() { #ISSTARTEDBYSYSTEM_START#
    _ppid=$PPID
    while true; do
        [ -z "$_ppid" ] && break
        _ppid=$(< "/proc/$_ppid/stat" awk '{print $4}')
        grep -Fq "cron" "/proc/$_ppid/comm" && return 0
        grep -Fq "hotplug" "/proc/$_ppid/comm" && return 0
        [ "$_ppid" -gt 1 ] || break
    done
    return 1
} #ISSTARTEDBYSYSTEM_END#

is_entware_mounted() {
    if mount | grep -Fq "on /opt "; then
        return 0
    else
        return 1
    fi
}

retry_command() {
    _command="$1"
    _retries="$2"
    _count=1
    [ -z "$_retries" ] && _retries=3

    while [ "$_count" -le "$_retries" ]; do
        if [ "$_count" -gt 1 ]; then
            echo "Command failed, retrying in 5 seconds..."
            sleep 5
        fi

        if $_command; then
            return 0
        fi

        _count=$((_count + 1))
    done

    echo "Command failed after $_retries attempts"
    return 1
}

init_opt() {
    [ -z "$1" ] && { echo "Target path not provided"; exit 1; }

    # Wait for app_init_run.sh to finish before messing with /opt mount
    timeout=60
    while /bin/ps w | grep -q "[a]pp_init_run.sh" && [ "$timeout" -ge 0 ]; do
        sleep 1
        timeout=$((timeout-1))
    done

    if [ -f "$1/etc/init.d/rc.unslung" ]; then
        if is_entware_mounted && ! umount /opt; then
            logger -st "$script_name" "Failed to unmount /opt"
            exit 1
        fi

        if mount --bind "$1" /opt; then
            if [ -z "$IN_RAM" ]; then # no need for this when running from RAM
                _mount_device="$(mount | grep -F "on /opt " | tail -n 1 | awk '{print $1}')"
                [ -n "$_mount_device" ] && basename "$_mount_device" > "$CACHE_FILE"
            fi

            logger -st "$script_name" "Mounted '$1' on /opt"
        else
            logger -st "$script_name" "Failed to mount '$1' on /opt"
            exit 1
        fi
    else
        logger -st "$script_name" "Entware not found in '$1'"
        exit 1
    fi
}

echo_and_log() {
    [ -z "$1" ] && { echo "Message is empty"; return 1; }
    [ -z "$2" ] && { echo "File is empty"; return 1; }

    echo "$1" 
    echo "$1" >> "$2"
}

backup_initd_scripts() {
    [ ! -d /opt/etc/init.d ] && return

    if [ -d "/tmp/$script_name-init.d-backup" ]; then
        rm -rf "/tmp/$script_name-init.d-backup/*"
    else
        mkdir -p "/tmp/$script_name-init.d-backup"
    fi

    # Copy rc.func, no modifications needed
    cp -f /opt/etc/init.d/rc.func "/tmp/$script_name-init.d-backup"

    # Copy and modify rc.unslung
    cp -f /opt/bin/find "/tmp/$script_name-init.d-backup"
    cp -f /opt/etc/init.d/rc.unslung "/tmp/$script_name-init.d-backup"
    sed "s#/opt/etc/init.d/#/tmp/$script_name-init.d-backup/#g" -i "/tmp/$script_name-init.d-backup/rc.unslung"
    sed "s#/opt/bin/find#/tmp/$script_name-init.d-backup/find#g" -i "/tmp/$script_name-init.d-backup/rc.unslung"

    for _file in /opt/etc/init.d/*; do
        [ ! -x "$_file" ] && continue

        case "$_file" in
            S*)
                cp -f "$_file" "/tmp/$script_name-init.d-backup/$_file"
                sed "s#/opt/etc/init.d/rc.func#/tmp/$script_name-init.d-backup/rc.func#g" -i "/tmp/$script_name-init.d-backup/$_file"
            ;;
        esac
    done
}

symlink_data() {
    if [ -d /jffs/entware ] && [ -n "$(ls -A /jffs/entware)" ]; then
        logger -st "$script_name" "Symlinking data from /jffs/entware..."

        find /jffs/entware -type f -exec sh -c '
            echo "$1" | grep -q "\.copythisfile$" && exit

            target_file="$(echo "$1" | sed "s@/jffs/entware@/opt@")"
            target_file_dir="$(dirname "$target_file")"

            [ "$(readlink -f "$target_file")" = "$(readlink -f "$1")" ] && exit

            # Prevent copying/symlinking files in directories marked to be symlinked
            TEST_DIR="$(dirname "$1")"
            MAXDEPTH=10
            while [ "$MAXDEPTH" -gt 0 ]; do
                [ -f "$TEST_DIR/.symlinkthisdir" ] && exit
                TEST_DIR="$(dirname "$TEST_DIR")"
                [ "$TEST_DIR" = "/jffs/entware" ] && break
                MAXDEPTH=$((MAXDEPTH-1))
            done

            if [ -f "$target_file" ]; then
                echo "Warning: File $target_file already exists, renaming..."
                [ -x "$target_file" ] && chmod -x "$target_file"
                mv -v "$target_file" "$target_file.bak_$(date +%s)"
            fi

            [ ! -d "$target_file_dir" ] && mkdir -pv "$target_file_dir"

            if [ -f "$1.copythisfile" ]; then
                cp -v "$1" "$target_file" || echo "Failed to copy a file: $target_file => $1"
            else
                ln -sv "$1" "$target_file" || echo "Failed to create a symlink: $target_file => $1"
            fi
        ' sh {} \;

        find /jffs/entware -type d -exec sh -c '
            [ ! -f "$1/.symlinkthisdir" ] && [ ! -f "$1/.copythisdir" ] && exit

            target_dir="$(echo "$1" | sed "s@/jffs/entware@/opt@")"
            target_dir_dir="$(dirname "$target_dir")"

            [ "$(readlink -f "$target_dir")" = "$(readlink -f "$1")" ] && exit

            if [ -d "$target_dir" ]; then
                echo "Warning: Directory $target_dir already exists, renaming..."
                mv -v "$target_dir" "$target_dir.bak_$(date +%s)"
            fi

            [ ! -d "$target_dir_dir" ] && mkdir -pv "$target_dir_dir"

            if [ -f "$1.copythisdir" ]; then
                cp -rv "$1" "$target_dir" || echo "Failed to copy a directory: $target_dir => $1"
            else
                ln -sv "$1" "$target_dir" || echo "Failed to create a symlink: $target_dir => $1"
            fi
        ' sh {} \;
    fi
}

services() {
    case "$1" in
        "start")
            if is_entware_mounted; then
                if [ -f /opt/etc/init.d/rc.unslung ]; then
                    logger -st "$script_name" "Starting services..."

                    /opt/etc/init.d/rc.unslung start "$script_path"

                    # this currently has been disabled due to some caveats...
                    #[ -z "$IN_RAM" ] && backup_initd_scripts
                else
                    logger -st "$script_name" "Unable to start services - Entware is not installed"
                fi
            else
                logger -st "$script_name" "Unable to start services - Entware is not mounted"
            fi
        ;;
        "stop")
            if [ -f /opt/etc/init.d/rc.unslung ]; then
                logger -st "$script_name" "Stopping services..."

                /opt/etc/init.d/rc.unslung stop "$script_path"
            elif [ -d "/tmp/$script_name-init.d-backup" ]; then
                logger -st "$script_name" "Killing services..."

                if "/tmp/$script_name-init.d-backup/rc.unslung" kill "$script_path"; then
                    rm -rf "/tmp/$script_name-init.d-backup"
                fi
            fi
        ;;
    esac
}

entware_in_ram() {
    # Prevent the log file from growing above 1MB
    if [ -f "$INSTALL_LOG" ] && [ "$(wc -c < "$INSTALL_LOG")" -gt 1048576 ]; then
        echo_and_log "Truncating $LOG_FILE to 1MB..." "$INSTALL_LOG"
        tail -c 1048576 "$LOG_FILE" > "$LOG_FILE.tmp" && mv "$LOG_FILE.tmp" "$LOG_FILE"
    fi

    if [ "$(nvram get wan0_state_t)" != "2" ] && [ "$(nvram get wan1_state_t)" != "2" ]; then
        echo_and_log "WAN network is not connected" "$INSTALL_LOG"
        return 1
    fi

    if [ -z "$($curl_binary -fs "$check_url" --retry 3)" ]; then
        echo_and_log "Cannot reach $check_url" "$INSTALL_LOG"
        return 1
    fi

    if [ ! -f /opt/etc/init.d/rc.unslung ]; then # is it not mounted?
        if [ ! -f /tmp/entware/etc/init.d/rc.unslung ]; then # is it not installed?
            logger -st "$script_name" "Installing Entware in /tmp/entware..."

            echo "---------- Installation started at $(date "+%Y-%m-%d %H:%M:%S") ----------" >> "$INSTALL_LOG"

            if ! sh "$script_path" install /tmp >> "$INSTALL_LOG" 2>&1; then
                logger -st "$script_name" "Installation failed, check '$INSTALL_LOG' for details"
                return 1
            fi

            echo "---------- Installation finished at $(date "+%Y-%m-%d %H:%M:%S") ----------" >> "$INSTALL_LOG"

            logger -st "$script_name" "Installation successful"
        fi

        # In case of script restart - /tmp/entware will already exist but won't be mounted
        ! is_entware_mounted && init_opt /tmp/entware

        logger -st "$script_name" "Starting services..."

        if ! /opt/etc/init.d/rc.unslung start "$script_path" >> "$INSTALL_LOG" 2>&1; then
            logger -st "$script_name" "Failed to start services, check '$INSTALL_LOG' for details"
        fi

        echo "---------- Services started at $(date "+%Y-%m-%d %H:%M:%S") ----------" >> "$INSTALL_LOG"
    fi

    return 0
}

entware() {
    lockfile lockwait

    case "$1" in
        "start")
            [ -z "$2" ] && { logger -st "$script_name" "Entware directory not provided"; exit 1; }

            init_opt "$2"
            services start
        ;;
        "stop")
            services stop

            if is_entware_mounted; then
                if umount /opt; then
                    logger -st "$script_name" "Unmounted /opt"
                else
                    logger -st "$script_name" "Failed to unmount /opt"
                fi
            fi

            echo "" > "$CACHE_FILE"
            last_entware_device=""
        ;;
    esac

    lockfile unlock
}

case "$1" in
    "run")
        { [ "$REQUIRE_NTP" = true ] && [ "$(nvram get ntp_ready)" != "1" ] ; } && { echo "Time is not synchronized"; exit 1; }

        if is_started_by_system && [ "$2" != "nohup" ]; then
            nohup "$script_path" run nohup > /dev/null 2>&1 &
        else
            if [ -n "$IN_RAM" ]; then
                lockfile lockfail inram || { echo "Already running! ($_lockpid)"; exit 1; }

                # Disable the cron job now as we will be running in a loop
                [ -x "$script_dir/cron-queue.sh" ] && sh "$script_dir/cron-queue.sh" remove "$script_name"
                cru d "$script_name"

                if [ ! -f /opt/etc/init.d/rc.unslung ]; then
                    echo "Will attempt to install for $WAIT_LIMIT minutes with 60 second intervals."

                    timeout="$WAIT_LIMIT"
                    while [ "$timeout" -ge 0 ]; do
                        [ "$timeout" -lt "$WAIT_LIMIT" ] && { echo "Unsuccessful installation, sleeping for 60 seconds..."; sleep 60; }

                        [ -f /opt/etc/init.d/rc.unslung ] && break # already mounted?
                        entware_in_ram && break # successfull?

                        timeout=$((timeout-1))
                    done

                    [ "$timeout" -le 0 ] && [ "$WAIT_LIMIT" != 0 ] && logger -st "$script_name" "Failed to install Entware (tried for $WAIT_LIMIT minutes)"
                fi

                lockfile unlock inram
            else
                if ! is_entware_mounted; then
                    for dir in /tmp/mnt/*; do
                        if [ -d "$dir/entware" ]; then
                            entware start "$dir/entware"
                            break
                        fi
                    done
                else
                    [ -z "$last_entware_device" ] && exit
                    # this currently has been disabled due to some caveats...
                    #[ -z "$IN_RAM" ] && backup_initd_scripts

                    target_path="$(mount | grep -F "$last_entware_device" | head -n 1 | awk '{print $3}')"

                    if [ -z "$target_path" ]; then # device/mount is gone
                        entware stop
                    fi
                fi
            fi
        fi
    ;;
    "hotplug")
        [ -n "$IN_RAM" ] && exit

        if [ "$(echo "$DEVICENAME" | cut -c 1-2)" = "sd" ]; then
            case "$ACTION" in
                "add")
                    is_entware_mounted && exit

                    target_path="$(mount | grep -F "$DEVICENAME" | head -n 1 | awk '{print $3}')"

                    if [ -d "$target_path/entware" ]; then
                        entware start "$target_path/entware"
                    fi
                ;;
                "remove")
                    if [ "$last_entware_device" = "$DEVICENAME" ]; then
                        entware stop
                    fi
                ;;
            esac

            sh "$script_path" run
        fi
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

        lockfile kill inram
        lockfile kill

        entware stop
    ;;
    "restart")
        sh "$script_path" stop
        sh "$script_path" start
    ;;
    "install")
        is_entware_mounted && { echo "Entware seems to be already mounted - unmount it before continuing"; exit 1; }

        for arg in "$@"; do
            [ "$arg" = "install" ] && continue
            arg_first="$(echo "$arg" | cut -c1)"

            if [ "$arg" = "alt" ]; then
                ALTERNATIVE=true
            elif [ "$arg_first" = "/" ] || [ "$arg_first" = "." ]; then
                target_path="$arg"
            else
                ARCHITECTURE=$arg
            fi
        done

        if [ -z "$target_path" ]; then
            for dir in /tmp/mnt/*; do
                if [ -d "$dir" ] && mount | grep -F "/dev" | grep -Fq "$dir"; then
                    target_path="$dir"
                    break
                fi
            done

            [ -z "$target_path" ] && { echo "Target path not provided"; exit 1; }

            echo "Detected mounted storage: $target_path"
        fi

        [ ! -d "$target_path" ] && { echo "Target path does not exist: $target_path"; exit 1; }
        [ -f "$target_path/entware/etc/init.d/rc.unslung" ] && { echo "Entware seems to be already installed in $target_path/entware"; exit 1; }

        if [ -z "$ARCHITECTURE" ]; then
            PLATFORM=$(uname -m)
            KERNEL=$(uname -r)

            case $PLATFORM in
                "aarch64")
                    ARCHITECTURE="aarch64-k3.10"
                ;;
                "armv5l")
                    ARCHITECTURE="armv5sf-k3.2"
                ;;
                "armv7l")
                    ARCHITECTURE="armv7sf-k2.6"

                    if [ "$(echo "$KERNEL" | cut -d'.' -f1)" -gt 2 ]; then
                        ARCHITECTURE="armv7sf-k3.2"
                    fi
                ;;
                "mipsel")
                    ARCHITECTURE="mipselsf-k3.4"
                ;;
                "mips")
                    ARCHITECTURE="mipssf-k3.4"
                ;;
                "x86_64"|"x64")
                    ARCHITECTURE="x64-k3.2"
                ;;
                "i386"|"i686"|"x86")
                    ARCHITECTURE="x86-k2.6"
                ;;
                *)
                    echo "Unsupported platform or failed to detect - provide supported architecture as an argument."
                    exit 1
                ;;
            esac

            echo "Detected architecture: $ARCHITECTURE"
        fi

        case "$ARCHITECTURE" in
            "aarch64-k3.10"|"armv5sf-k3.2"|"armv7sf-k2.6"|"armv7sf-k3.2"|"mipselsf-k3.4"|"mipssf-k3.4"|"x64-k3.2"|"x86-k2.6")
                install_url="http://$BASE_URL/$ARCHITECTURE/installer"
            ;;
            #"mipsel"|"armv5"|"armv7"|"x86-32"|"x86-64")
            #    install_url="http://pkg.entware.net/binaries/$ARCHITECTURE/installer"
            #;;
            #"mips")
            #    install_url="http://pkg.entware.net/binaries/mipsel/installer"
            #;;
            *)
                echo "Unsupported architecture: $ARCHITECTURE";
                exit 1;
            ;;
        esac

        [ "$USE_HTTPS" = true ] && install_url="$(echo "$install_url" | sed 's/http:/https:/')"

        echo
        echo "Will install Entware to $target_path from $install_url"
        [ "$ALTERNATIVE" = true ] && echo "Using alternative install (separated users from the system)"

        if [ -z "$IN_RAM" ] && [ "$(readlink -f /proc/$$/fd/0 2> /dev/null)" != "/dev/null" ]; then
            echo "You can override target path and architecture by providing them as arguments."

            echo
            #shellcheck disable=SC3045,SC2162
            read -p "Press any key to continue or CTRL-C to cancel... " -n1
            echo
        fi

        set -e

        echo "Checking and creating required directories..."

        [ ! -d "$target_path/entware" ] && mkdir -v "$target_path/entware"
        mount --bind "$target_path/entware" /opt && echo "Mounted $target_path/entware on /opt"

        for dir in bin etc lib/opkg tmp var/lock; do
            if [ ! -d "/opt/$dir" ]; then
                mkdir -pv /opt/$dir
            fi
        done

        PATH=/opt/bin:/opt/sbin:/opt/usr/bin:$PATH

        echo "Installing package manager..."

        if [ ! -f /opt/bin/opkg ]; then
            curl -fsS "$install_url/opkg" -o /opt/bin/opkg
            chmod 755 /opt/bin/opkg
            echo "'$install_url/opkg' -> '/opt/bin/opkg'"
        fi

        if [ ! -f /opt/etc/opkg.conf ]; then
            if [ -n "$IN_RAM" ] && [ -f /jffs/entware/etc/opkg.conf ]; then
                ln -sv /jffs/entware/etc/opkg.conf /opt/etc/opkg.conf
            else
                curl -fsS "$install_url/opkg.conf" -o /opt/etc/opkg.conf
                echo "'$install_url/opkg.conf' -> '/opt/etc/opkg.conf'"

                [ "$BASE_URL" != "$default_base_url" ] && sed "s#$default_base_url:#$BASE_URL:#g" -i /opt/etc/opkg.conf
                [ "$USE_HTTPS" = true ] && sed 's/http:/https:/g' -i /opt/etc/opkg.conf
            fi
        fi

        echo "Updating package lists..."
        retry_command "opkg update"

        echo "Installing core packages..."

        [ "$ALTERNATIVE" = true ] && retry_command "opkg install busybox"
        retry_command "opkg install entware-opt"

        # Fix /opt/tmp permissions because entware-opt sets them to 755
        chmod 777 /opt/tmp

        echo "Checking and copying required files..."

        for file in passwd group shells shadow gshadow; do
            if [ "$ALTERNATIVE" != true ] && [ -f "/etc/$file" ]; then
                ln -sfv "/etc/$file" "/opt/etc/$file"
            else
                [ -f "/opt/etc/$file.1" ] && cp -v "/opt/etc/$file.1" "/opt/etc/$file"
            fi
        done

        [ -f /etc/localtime ] && ln -sfv /etc/localtime /opt/etc/localtime

        if [ -n "$IN_RAM" ]; then
            echo "Installing selected packages..."

            #shellcheck disable=SC2086
            retry_command "opkg install $IN_RAM"

            symlink_data
        fi

        echo "Installation complete!"
    ;;
    "symlinks")
        if [ -n "$IN_RAM" ]; then
            symlink_data
        else
            echo "This function is only supported when installing Entware in RAM."
        fi
    ;;
    *)
        echo "Usage: $0 run|start|stop|restart|install|symlinks"
        exit 1
    ;;
esac
