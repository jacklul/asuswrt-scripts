#!/bin/sh
# Made by Jack'lul <jacklul.github.io>
#
# Enable Entware on startup, with installer included
#
# Based on:
#  https://bin.entware.net/armv7sf-k3.2/installer/generic.sh
#  https://raw.githubusercontent.com/RMerl/asuswrt-merlin.ng/a46283c8cbf2cdd62d8bda231c7a79f5a2d3b889/release/src/router/others/entware-setup.sh
#

#jas-update=entware.sh
#shellcheck disable=SC2155
#shellcheck source=./common.sh
readonly common_script="$(dirname "$0")/common.sh"
if [ -f "$common_script" ]; then . "$common_script"; else { echo "$common_script not found"; exit 1; } fi

IN_RAM="" # Install Entware and packages in RAM (/tmp), space separated list
ARCHITECTURE="" # Entware architecture, set it only when auto install (to /tmp) can't detect it properly
ALTERNATIVE=false # Perform alternative install (separated users from the system)
USE_HTTPS=true # retrieve files using HTTPS, applies to OPKG repository and installation downloads
BASE_URL="http://bin.entware.net" # Base Entware URL, can be changed if you wish to use a different mirror (no ending slash!)
WAIT_LIMIT=60 # how many minutes to wait for auto install before giving up (in RAM only), set to 0 to only attempt once
INSTALL_LOG="/tmp/entware-install.log" # where to store installation log (in RAM only)
REQUIRE_NTP=true # require time to be synchronized to start
ENTWARE_DIR=entware # in case you want to change the directory name on the storage drive
STATE_FILE="$TMP_DIR/$script_name" # where to store last device Entware was mounted on

load_script_config

default_base_url="http://bin.entware.net" # hardcoded in opkg.conf
last_entware_device=""
[ -f "$STATE_FILE" ] && last_entware_device="$(cat "$STATE_FILE")"
[ -z "$BASE_URL" ] && BASE_URL="$default_base_url"
check_url="http://$BASE_URL"
[ "$USE_HTTPS" = true ] && check_url="$(echo "$check_url" | sed 's/http:/https:/')"
[ -z "$WAIT_LIMIT" ] && WAIT_LIMIT=0 # only one attempt

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

unmount_opt() {
    _timer=60
    while [ "$_timer" -gt 0 ] ; do
        umount /opt 2> /dev/null && return 0
        _timer=$((_timer-1))
        sleep 1
    done

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
        if is_entware_mounted; then
            if ! unmount_opt; then
                logecho "Failed to unmount /opt"
                exit 1
            fi
        fi

        if mount --bind "$1" /opt; then
            if [ -z "$IN_RAM" ]; then # no need for this when running from RAM
                _mount_device="$(mount | grep -F "on /opt " | tail -n 1 | awk '{print $1}')"
                [ -n "$_mount_device" ] && basename "$_mount_device" > "$STATE_FILE"
            fi

            logecho "Mounted '$1' on /opt" true
        else
            logecho "Failed to mount '$1' on /opt"
            exit 1
        fi
    else
        logecho "Entware not found in '$1'"
        exit 1
    fi
}

backup_initd_scripts() {
    [ ! -d /opt/etc/init.d ] && return

    if [ -d "/tmp/$script_name-init.d-backup" ]; then
        rm -rf "/tmp/$script_name-init.d-backup/*"
    else
        #shellcheck disable=SC2174
        mkdir -p 755 "/tmp/$script_name-init.d-backup"
    fi

    # Copy rc.func, no modifications needed
    cp -f /opt/etc/init.d/rc.func "/tmp/$script_name-init.d-backup"

    # Copy and modify rc.unslung
    cp -f /opt/bin/find "/tmp/$script_name-init.d-backup"
    cp -f /opt/etc/init.d/rc.unslung "/tmp/$script_name-init.d-backup"
    sed_helper replace "/opt/etc/init.d/" "/tmp/$script_name-init.d-backup/" "/tmp/$script_name-init.d-backup/rc.unslung"
    sed_helper replace "/opt/bin/find" "/tmp/$script_name-init.d-backup/find" "/tmp/$script_name-init.d-backup/rc.unslung"

    for _file in /opt/etc/init.d/*; do
        [ ! -x "$_file" ] && continue

        case "$_file" in
            S*)
                cp -f "$_file" "/tmp/$script_name-init.d-backup/$_file"
                sed_helper replace "/opt/etc/init.d/rc.func" "/tmp/$script_name-init.d-backup/rc.func" "/tmp/$script_name-init.d-backup/$_file"
            ;;
        esac
    done
}

services() {
    case "$1" in
        "start")
            if is_entware_mounted; then
                if [ -f /opt/etc/init.d/rc.unslung ]; then
                    logecho "Starting services..." true

                    /opt/etc/init.d/rc.unslung start "$script_path"

                    # this currently has been disabled due to some caveats...
                    #[ -z "$IN_RAM" ] && backup_initd_scripts
                else
                    logecho "Unable to start services - Entware is not installed"
                    return 1
                fi
            else
                logecho "Unable to start services - Entware is not mounted"
                return 1
            fi
        ;;
        "stop")
            if [ -f /opt/etc/init.d/rc.unslung ]; then
                logecho "Stopping services..." true

                /opt/etc/init.d/rc.unslung stop "$script_path"
            elif [ -d "/tmp/$script_name-init.d-backup" ]; then
                logecho "Killing services..." true

                if "/tmp/$script_name-init.d-backup/rc.unslung" kill "$script_path"; then
                    rm -rf "/tmp/$script_name-init.d-backup"
                fi
            fi
        ;;
    esac

    return 0
}

entware() {
    lockfile lockwait

    case "$1" in
        "start")
            [ -z "$2" ] && { echo "Entware directory not provided"; exit 1; }

            init_opt "$2"

            if services start; then
                # Delete crontab entry after successful launch when hotplug-event script is available
                execute_script_basename "hotplug-event.sh" check && crontab_entry delete
            fi
        ;;
        "stop")
            services stop

            if is_entware_mounted; then
                if unmount_opt; then
                    logecho "Unmounted /opt" true
                else
                    logecho "Failed to unmount /opt"
                fi
            fi

            echo "" > "$STATE_FILE"
            last_entware_device=""
        ;;
    esac

    lockfile unlock
}

echo_and_log() {
    [ -z "$1" ] && { echo "Message is empty"; return 1; }
    [ -z "$2" ] && { echo "File is empty"; return 1; }

    echo "$1"
    echo "$1" >> "$2"
}

symlink_data() {
    if [ -d /jffs/entware ] && [ -n "$(ls -A /jffs/entware)" ]; then
        logecho "Symlinking data from /jffs/entware..."

        find /jffs/entware -exec sh -c '
            [ ! -f "$1" ] && exit
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

        find /jffs/entware -exec sh -c '
            [ ! -d "$1" ] && exit
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

entware_in_ram() {
    [ -z "$INSTALL_LOG" ] && { logecho "Error: Install log file is not set"; exit 1; }

    # Prevent the log file from growing above 1MB
    if [ -f "$INSTALL_LOG" ] && [ "$(wc -c < "$INSTALL_LOG")" -gt 1048576 ]; then
        echo_and_log "Truncating $LOG_FILE to 1MB..." "$INSTALL_LOG"
        tail -c 1048576 "$LOG_FILE" > "$LOG_FILE.tmp" && mv "$LOG_FILE.tmp" "$LOG_FILE"
    fi

    if [ "$(nvram get wan0_state_t)" != "2" ] && [ "$(nvram get wan1_state_t)" != "2" ]; then
        echo_and_log "WAN network is not connected" "$INSTALL_LOG"
        return 1
    fi

    if [ -z "$(fetch "$check_url")" ]; then
        echo_and_log "Cannot reach $check_url" "$INSTALL_LOG"
        return 1
    fi

    if [ ! -f /opt/etc/init.d/rc.unslung ]; then # is it not mounted?
        if [ ! -f /tmp/entware/etc/init.d/rc.unslung ]; then # is it not installed?
            logecho "Installing Entware in /tmp/entware..."

            echo "---------- Installation started at $(date "+%Y-%m-%d %H:%M:%S") ----------" >> "$INSTALL_LOG"

            if ! sh "$script_path" install /tmp >> "$INSTALL_LOG" 2>&1; then
                logecho "Installation failed, check '$INSTALL_LOG' for details"
                return 1
            fi

            echo "---------- Installation finished at $(date "+%Y-%m-%d %H:%M:%S") ----------" >> "$INSTALL_LOG"

            logecho "Installation successful"
        fi

        # In case of script restart - /tmp/entware will already exist but won't be mounted
        ! is_entware_mounted && init_opt /tmp/entware

        logecho "Starting services..."

        if ! /opt/etc/init.d/rc.unslung start "$script_path" >> "$INSTALL_LOG" 2>&1; then
            logecho "Failed to start services, check '$INSTALL_LOG' for details"
        fi

        echo "---------- Services started at $(date "+%Y-%m-%d %H:%M:%S") ----------" >> "$INSTALL_LOG"
    fi

    return 0
}

entware_init() {
    { [ "$REQUIRE_NTP" = true ] && [ "$(nvram get ntp_ready)" != "1" ] ; } && { echo "Time is not synchronized"; exit 1; }

    if [ -n "$IN_RAM" ]; then
        lockfile lockfail inram || { echo "Already running! ($lockpid)"; exit 1; }

        # Disable the cron job now as we will be running in a loop
        # There will be no reason to keep the cronjob active after Entware is initialized in tmpfs
        crontab_entry delete

        if [ ! -f /opt/etc/init.d/rc.unslung ]; then
            echo "Will attempt to install for $WAIT_LIMIT minutes with 60 second intervals."

            timeout="$WAIT_LIMIT"
            while [ "$timeout" -ge 0 ]; do
                [ "$timeout" -lt "$WAIT_LIMIT" ] && { echo "Unsuccessful installation, sleeping for 60 seconds..."; sleep 60; }
                [ -f /opt/etc/init.d/rc.unslung ] && break # already mounted?
                entware_in_ram && break # successfull?
                timeout=$((timeout-1))
            done

            [ "$timeout" -le 0 ] && [ "$WAIT_LIMIT" != 0 ] && logecho "Failed to install Entware (tried for $WAIT_LIMIT minutes)"
        fi

        lockfile unlock inram
    else
        if ! is_entware_mounted; then
            for dir in /tmp/mnt/*; do
                if [ -d "$dir/$ENTWARE_DIR" ]; then
                    entware start "$dir/$ENTWARE_DIR"
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
}

run_in_background() {
    lockfile check && { echo "Already running! ($lockpid)"; exit 1; }

    if [ -n "$IN_RAM" ] && is_started_by_system && [ "$PPID" -ne 1 ]; then
        nohup "$script_path" run > /dev/null 2>&1 &
    else
        entware_init
    fi
}

case "$1" in
    "run")
        run_in_background
    ;;
    "hotplug")
        [ -n "$IN_RAM" ] && exit

        if [ "$SUBSYSTEM" = "block" ] && [ -n "$DEVICENAME" ]; then
            case "$ACTION" in
                "add")
                    is_entware_mounted && exit

                    target_path="$(mount | grep -F "$DEVICENAME" | head -n 1 | awk '{print $3}')"

                    if [ -d "$target_path/$ENTWARE_DIR" ]; then
                        entware start "$target_path/$ENTWARE_DIR"
                    fi
                ;;
                "remove")
                    if [ "$last_entware_device" = "$DEVICENAME" ]; then
                        entware stop
                    fi
                ;;
            esac
        fi
    ;;
    "start")
        crontab_entry add "*/1 * * * * $script_path run"

        if is_started_by_system; then
            run_in_background
        else
            entware_init
        fi
    ;;
    "stop")
        crontab_entry delete
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
            arg_first="$(echo "$arg" | cut -c 1)"

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
        [ -f "$target_path/$ENTWARE_DIR/etc/init.d/rc.unslung" ] && { echo "Entware seems to be already installed in $target_path/$ENTWARE_DIR"; exit 1; }

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

                    if [ "$(echo "$KERNEL" | cut -d '.' -f 1)" -gt 2 ]; then
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
            *)
                echo "Unsupported architecture: $ARCHITECTURE";
                exit 1;
            ;;
        esac

        if [ "$USE_HTTPS" = true ]; then selection="Y/n"; else selection="y/N"; fi

        #shellcheck disable=SC3045,SC2162
        read -p "Do you wish to use HTTPS? [$selection] " response
        case "$response" in
            [Yy]*|[Yy][Ee][Ss]*) USE_HTTPS=true ;;
            [Nn]*|[Nn][Oo]*) USE_HTTPS=false ;;
            *) ;;
        esac

        if [ "$USE_HTTPS" = true ]; then
            echo "Will use HTTPS for downloads and OPKG configuration."
            install_url="$(echo "$install_url" | sed 's/http:/https:/')"
        else
            echo "Will use HTTP for downloads and OPKG configuration."
        fi

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

        [ ! -d "$target_path/$ENTWARE_DIR" ] && mkdir -v "$target_path/$ENTWARE_DIR"
        mount --bind "$target_path/$ENTWARE_DIR" /opt && echo "Mounted $target_path/$ENTWARE_DIR on /opt"

        for dir in bin etc lib/opkg tmp var/lock; do
            if [ ! -d "/opt/$dir" ]; then
                #shellcheck disable=SC2174
                mkdir -pvm 755 /opt/$dir
            fi
        done

        PATH=/opt/bin:/opt/sbin:/opt/usr/bin:$PATH

        echo "Installing package manager..."

        if [ ! -f /opt/bin/opkg ]; then
            fetch "$install_url/opkg" /opt/bin/opkg
            chmod 755 /opt/bin/opkg
            echo "'$install_url/opkg' -> '/opt/bin/opkg'"
        fi

        if [ ! -f /opt/etc/opkg.conf ]; then
            if [ -n "$IN_RAM" ] && [ -f /jffs/entware/etc/opkg.conf ]; then
                ln -sv /jffs/entware/etc/opkg.conf /opt/etc/opkg.conf
            else
                fetch "$install_url/opkg.conf" /opt/etc/opkg.conf
                echo "'$install_url/opkg.conf' -> '/opt/etc/opkg.conf'"

                [ "$BASE_URL" != "$default_base_url" ] && sed_helper replace "$default_base_url" "$BASE_URL" /opt/etc/opkg.conf
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
