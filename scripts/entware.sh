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

readonly SCRIPT_PATH="$(readlink -f "$0")"
readonly SCRIPT_NAME="$(basename "$SCRIPT_PATH" .sh)"
readonly SCRIPT_DIR="$(dirname "$SCRIPT_PATH")"
readonly SCRIPT_CONFIG="$SCRIPT_DIR/$SCRIPT_NAME.conf"
readonly SCRIPT_TAG="$(basename "$SCRIPT_PATH")"

IN_RAM="" # Install Entware and packages in RAM (/tmp), space separated list
ARCHITECTURE="" # Entware architecture, set it only when auto install (to /tmp) can't detect it properly
ALTERNATIVE=false # Perform alternative install (separated users from the system)
USE_HTTPS=false # retrieve files using HTTPS, applies to OPKG repository and installation downloads
BASE_URL="bin.entware.net" # Base Entware URL, can be changed if you wish to use a different mirror (no http/https prefix and no ending slash!)
WAIT_LIMIT=60 # how many minutes to wait for auto install before giving up (in RAM only)
CACHE_FILE="/tmp/last_entware_device" # where to store last device Entware was mounted on
INSTALL_LOG="/tmp/entware-install.log" # where to store installation log (in RAM only)

if [ -f "$SCRIPT_CONFIG" ]; then
    #shellcheck disable=SC1090
    . "$SCRIPT_CONFIG"
fi

DEFAULT_BASE_URL="bin.entware.net" # hardcoded in opkg.conf
LAST_ENTWARE_DEVICE=""
[ -f "$CACHE_FILE" ] && LAST_ENTWARE_DEVICE="$(cat "$CACHE_FILE")"
CHECK_URL="http://$BASE_URL"
[ "$USE_HTTPS" = true ] && CHECK_URL="$(echo "$CHECK_URL" | sed 's/http:/https:/')"
CURL_BINARY="curl"
#[ -f /opt/bin/curl ] && CURL_BINARY="/opt/bin/curl" # what was I thinking here?

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
                    flock -x "$_FD"
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

is_started_by_system() { #ISSTARTEDBYSYSTEM_START#
    _PPID=$PPID
    while true; do
        [ -z "$_PPID" ] && break
        _PPID=$(< "/proc/$_PPID/stat" awk '{print $4}')

        grep -q "cron" "/proc/$_PPID/comm" && return 0
        grep -q "hotplug" "/proc/$_PPID/comm" && return 0
        [ "$_PPID" -gt 1 ] || break
    done

    return 1
} #ISSTARTEDBYSYSTEM_END#

is_entware_mounted() {
    if mount | grep -q "on /opt "; then
        return 0
    else
        return 1
    fi
}

retry_command() {
    _COMMAND="$1"
    _RETRIES="$2"
    _COUNT=1
    [ -z "$_RETRIES" ] && _RETRIES=3

    while [ "$_COUNT" -le "$_RETRIES" ]; do
        if [ "$_COUNT" -gt 1 ]; then
            echo "Command failed, retrying in 5 seconds..."
            sleep 5
        fi

        if $_COMMAND; then
            return 0
        fi

        _COUNT=$((_COUNT + 1))
    done

    echo "Command failed after $_RETRIES attempts"
    return 1
}

init_opt() {
    [ -z "$1" ] && { echo "Target path not provided"; exit 1; }

    if [ -f "$1/etc/init.d/rc.unslung" ]; then
        if is_entware_mounted && ! umount /opt; then
            logger -st "$SCRIPT_TAG" "Failed to unmount /opt"
            exit 1
        fi

        if mount --bind "$1" /opt; then
            if [ -z "$IN_RAM" ]; then # no need for this when running from RAM
                MOUNT_DEVICE="$(mount | grep "on /opt " | tail -n 1 | awk '{print $1}')"
                [ -n "$MOUNT_DEVICE" ] && basename "$MOUNT_DEVICE" > "$CACHE_FILE"
            fi

            logger -st "$SCRIPT_TAG" "Mounted $1 on /opt"
        else
            logger -st "$SCRIPT_TAG" "Failed to mount $1 on /opt"
            exit 1
        fi
    else
        logger -st "$SCRIPT_TAG" "Entware not found in $1"
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

    if [ -d "/tmp/$SCRIPT_NAME-init.d-backup" ]; then
        rm -rf "/tmp/$SCRIPT_NAME-init.d-backup/*"
    else
        mkdir -p "/tmp/$SCRIPT_NAME-init.d-backup"
    fi

    # Copy rc.func, no modifications needed
    cp -f /opt/etc/init.d/rc.func "/tmp/$SCRIPT_NAME-init.d-backup"

    # Copy and modify rc.unslung
    cp -f /opt/bin/find "/tmp/$SCRIPT_NAME-init.d-backup"
    cp -f /opt/etc/init.d/rc.unslung "/tmp/$SCRIPT_NAME-init.d-backup"
    sed "s#/opt/etc/init.d/#/tmp/$SCRIPT_NAME-init.d-backup/#g" -i "/tmp/$SCRIPT_NAME-init.d-backup/rc.unslung"
    sed "s#/opt/bin/find#/tmp/$SCRIPT_NAME-init.d-backup/find#g" -i "/tmp/$SCRIPT_NAME-init.d-backup/rc.unslung"

    for FILE in /opt/etc/init.d/*; do
        [ ! -x "$FILE" ] && continue

        case "$FILE" in
            S*)
                cp -f "$FILE" "/tmp/$SCRIPT_NAME-init.d-backup/$FILE"
                sed "s#/opt/etc/init.d/rc.func#/tmp/$SCRIPT_NAME-init.d-backup/rc.func#g" -i "/tmp/$SCRIPT_NAME-init.d-backup/$FILE"
            ;;
        esac
    done
}

symlink_data() {
    if [ -d /jffs/entware ] && [ -n "$(ls -A /jffs/entware)" ]; then
        echo "Symlinking data from /jffs/entware..."

        find /jffs/entware -type f -exec sh -c '
            echo "$1" | grep -q "\.copythisfile$" && exit

            TARGET_FILE="$(echo "$1" | sed "s@/jffs/entware@/opt@")"
            TARGET_FILE_DIR="$(dirname "$TARGET_FILE")"

            [ "$(readlink -f "$TARGET_FILE")" = "$(readlink -f "$1")" ] && exit

            # Prevent copying/symlinking files in directories marked to be symlinked
            TEST_DIR="$(dirname "$1")"
            MAXDEPTH=10
            while [ "$MAXDEPTH" -gt 0 ]; do
                [ -f "$TEST_DIR/.symlinkthisdir" ] && exit
                TEST_DIR="$(dirname "$TEST_DIR")"
                [ "$TEST_DIR" = "/jffs/entware" ] && break
                MAXDEPTH=$((MAXDEPTH-1))
            done

            if [ -f "$TARGET_FILE" ]; then
                echo "Warning: File $TARGET_FILE already exists, renaming..."
                [ -x "$TARGET_FILE" ] && chmod -x "$TARGET_FILE"
                mv -v "$TARGET_FILE" "$TARGET_FILE.bak_$(date +%s)"
            fi

            [ ! -d "$TARGET_FILE_DIR" ] && mkdir -pv "$TARGET_FILE_DIR"

            if [ -f "$1.copythisfile" ]; then
                cp -v "$1" "$TARGET_FILE" || echo "Failed to copy a file: $TARGET_FILE => $1"
            else
                ln -sv "$1" "$TARGET_FILE" || echo "Failed to create a symlink: $TARGET_FILE => $1"
            fi
        ' sh {} \;

        find /jffs/entware -type d -exec sh -c '
            [ ! -f "$1/.symlinkthisdir" ] && [ ! -f "$1/.copythisdir" ] && exit

            TARGET_DIR="$(echo "$1" | sed "s@/jffs/entware@/opt@")"
            TARGET_DIR_DIR="$(dirname "$TARGET_DIR")"

            [ "$(readlink -f "$TARGET_DIR")" = "$(readlink -f "$1")" ] && exit

            if [ -d "$TARGET_DIR" ]; then
                echo "Warning: Directory $TARGET_DIR already exists, renaming..."
                mv -v "$TARGET_DIR" "$TARGET_DIR.bak_$(date +%s)"
            fi

            [ ! -d "$TARGET_DIR_DIR" ] && mkdir -pv "$TARGET_DIR_DIR"

            if [ -f "$1.copythisdir" ]; then
                cp -rv "$1" "$TARGET_DIR" || echo "Failed to copy a directory: $TARGET_DIR => $1"
            else
                ln -sv "$1" "$TARGET_DIR" || echo "Failed to create a symlink: $TARGET_DIR => $1"
            fi
        ' sh {} \;
    fi
}

services() {
    case "$1" in
        "start")
            if is_entware_mounted; then
                if [ -f /opt/etc/init.d/rc.unslung ]; then
                    logger -st "$SCRIPT_TAG" "Starting services..."

                    /opt/etc/init.d/rc.unslung start "$SCRIPT_PATH"

                    # this currently has been disabled due to some caveats...
                    #[ -z "$IN_RAM" ] && backup_initd_scripts
                else
                    logger -st "$SCRIPT_TAG" "Unable to start services - Entware is not installed"
                fi
            else
                logger -st "$SCRIPT_TAG" "Unable to start services - Entware is not mounted"
            fi
        ;;
        "stop")
            if [ -f /opt/etc/init.d/rc.unslung ]; then
                logger -st "$SCRIPT_TAG" "Stopping services..."

                /opt/etc/init.d/rc.unslung stop "$SCRIPT_PATH"
            elif [ -d "/tmp/$SCRIPT_NAME-init.d-backup" ]; then
                logger -st "$SCRIPT_TAG" "Killing services..."

                if "/tmp/$SCRIPT_NAME-init.d-backup/rc.unslung" kill "$SCRIPT_PATH"; then
                    rm -rf "/tmp/$SCRIPT_NAME-init.d-backup"
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

    if [ -z "$($CURL_BINARY -fs "$CHECK_URL" --retry 3)" ]; then
        echo_and_log "Cannot reach $CHECK_URL" "$INSTALL_LOG"
        return 1
    fi

    if [ ! -f /opt/etc/init.d/rc.unslung ]; then # is it not mounted?
        if [ ! -f /tmp/entware/etc/init.d/rc.unslung ]; then # is it not installed?
            logger -st "$SCRIPT_TAG" "Installing Entware in /tmp/entware..."

            echo "---------- Installation started at $(date) ----------" >> "$INSTALL_LOG"

            if ! sh "$SCRIPT_PATH" install /tmp >> "$INSTALL_LOG" 2>&1; then
                logger -st "$SCRIPT_TAG" "Installation failed, check '$INSTALL_LOG' for details"

                # Prevent cron job from retrying failed install, if scheduled
                [ -x "$SCRIPT_DIR/cron-queue.sh" ] && sh "$SCRIPT_DIR/cron-queue.sh" remove "$SCRIPT_NAME"
                cru d "$SCRIPT_NAME"

                return 1
            fi

            echo "---------- Installation finished at $(date) ----------" >> "$INSTALL_LOG"

            logger -st "$SCRIPT_TAG" "Installation successful"
        fi

        # In case of script restart - /tmp/entware will already exist but won't be mounted
        ! is_entware_mounted && init_opt /tmp/entware

        logger -st "$SCRIPT_TAG" "Starting services..."

        if ! /opt/etc/init.d/rc.unslung start "$SCRIPT_PATH" >> "$INSTALL_LOG" 2>&1; then
            logger -st "$SCRIPT_TAG" "Failed to start services, check $INSTALL_LOG for details"
        fi

        echo "---------- Services started at $(date) ----------" >> "$INSTALL_LOG"
    fi

    return 0
}

entware() {
    lockfile lockwait

    case "$1" in
        "start")
            [ -z "$2" ] && { logger -st "$SCRIPT_TAG" "Entware directory not provided"; exit 1; }

            init_opt "$2"
            services start
        ;;
        "stop")
            services stop

            if is_entware_mounted; then
                if umount /opt; then
                    logger -st "$SCRIPT_TAG" "Unmounted /opt"
                else
                    logger -st "$SCRIPT_TAG" "Failed to unmount /opt"
                fi
            fi

            echo "" > "$CACHE_FILE"
            LAST_ENTWARE_DEVICE=""
        ;;
    esac

    lockfile unlock
}

case "$1" in
    "run")
        if [ -n "$IN_RAM" ]; then
            lockfile lockfail inram || { echo "Already running! ($_LOCKPID)"; exit 1; }

            if [ ! -f /opt/etc/init.d/rc.unslung ]; then
                echo "Will attempt to install for $WAIT_LIMIT minutes with 60 second intervals."

                TIMEOUT="$WAIT_LIMIT"
                while [ "$TIMEOUT" -ge 0 ]; do
                    [ "$TIMEOUT" -lt "$WAIT_LIMIT" ] && { echo "Unsuccessful installation, sleeping for 60 seconds..."; sleep 60; }

                    [ -f /opt/etc/init.d/rc.unslung ] && break # already mounted?
                    entware_in_ram && break # successfull?

                    TIMEOUT=$((TIMEOUT-1))
                done

                [ "$TIMEOUT" -le 0 ] && [ "$WAIT_LIMIT" != 0 ] && logger -st "$SCRIPT_TAG" "Failed to install Entware (tried for $WAIT_LIMIT minutes)"

                lockfile unlock inram
            fi
        else
            if ! is_entware_mounted; then
                for DIR in /tmp/mnt/*; do
                    if [ -d "$DIR/entware" ]; then
                        entware start "$DIR/entware"
                        break
                    fi
                done
            else
                [ -z "$LAST_ENTWARE_DEVICE" ] && exit
                # this currently has been disabled due to some caveats...
                #[ -z "$IN_RAM" ] && backup_initd_scripts

                TARGET_PATH="$(mount | grep "$LAST_ENTWARE_DEVICE" | head -n 1 | awk '{print $3}')"

                if [ -z "$TARGET_PATH" ]; then # device/mount is gone
                    entware stop
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

                    TARGET_PATH="$(mount | grep "$DEVICENAME" | head -n 1 | awk '{print $3}')"

                    if [ -d "$TARGET_PATH/entware" ]; then
                        entware start "$TARGET_PATH/entware"
                    fi
                ;;
                "remove")
                    if [ "$LAST_ENTWARE_DEVICE" = "$DEVICENAME" ]; then
                        entware stop
                    fi
                ;;
                *)
                    logger -st "$SCRIPT_TAG" "Unknown hotplug action: $ACTION ($DEVICENAME)"
                    exit 1
                ;;
            esac

            sh "$SCRIPT_PATH" run
        fi
    ;;
    "start")
        if [ -z "$IN_RAM" ]; then
            if [ -x "$SCRIPT_DIR/cron-queue.sh" ]; then
                sh "$SCRIPT_DIR/cron-queue.sh" add "$SCRIPT_NAME" "$SCRIPT_PATH run"
            else
                cru a "$SCRIPT_NAME" "*/1 * * * * $SCRIPT_PATH run"
            fi
        fi

        if is_started_by_system; then
            nohup "$SCRIPT_PATH" run > /dev/null 2>&1 &
        else
            sh "$SCRIPT_PATH" run
        fi
    ;;
    "stop")
        [ -x "$SCRIPT_DIR/cron-queue.sh" ] && sh "$SCRIPT_DIR/cron-queue.sh" remove "$SCRIPT_NAME"
        cru d "$SCRIPT_NAME"

        lockfile kill inram
        lockfile kill

        entware stop
    ;;
    "restart")
        sh "$SCRIPT_PATH" stop
        sh "$SCRIPT_PATH" start
    ;;
    "install")
        is_entware_mounted && { echo "Entware seems to be already mounted - unmount it before continuing"; exit 1; }

        for ARG in "$@"; do
            [ "$ARG" = "install" ] && continue
            ARG_FIRST="$(echo "$ARG" | cut -c1)"

            if [ "$ARG" = "alt" ]; then
                ALTERNATIVE=true
            elif [ "$ARG_FIRST" = "/" ] || [ "$ARG_FIRST" = "." ]; then
                TARGET_PATH="$ARG"
            else
                ARCHITECTURE=$ARG
            fi
        done

        if [ -z "$TARGET_PATH" ]; then
            for DIR in /tmp/mnt/*; do
                if [ -d "$DIR" ] && mount | grep "/dev" | grep -q "$DIR"; then
                    TARGET_PATH="$DIR"
                    break
                fi
            done

            [ -z "$TARGET_PATH" ] && { echo "Target path not provided"; exit 1; }

            echo "Detected mounted storage: $TARGET_PATH"
        fi

        [ ! -d "$TARGET_PATH" ] && { echo "Target path does not exist: $TARGET_PATH"; exit 1; }
        [ -f "$TARGET_PATH/entware/etc/init.d/rc.unslung" ] && { echo "Entware seems to be already installed in $TARGET_PATH/entware"; exit; }

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
                INSTALL_URL="http://$BASE_URL/$ARCHITECTURE/installer"
            ;;
            #"mipsel"|"armv5"|"armv7"|"x86-32"|"x86-64")
            #    INSTALL_URL="http://pkg.entware.net/binaries/$ARCHITECTURE/installer"
            #;;
            #"mips")
            #    INSTALL_URL="http://pkg.entware.net/binaries/mipsel/installer"
            #;;
            *)
                echo "Unsupported architecture: $ARCHITECTURE";
                exit 1;
            ;;
        esac

        [ "$USE_HTTPS" = true ] && INSTALL_URL="$(echo "$INSTALL_URL" | sed 's/http:/https:/')"

        echo
        echo "Will install Entware to $TARGET_PATH from $INSTALL_URL"
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

        [ ! -d "$TARGET_PATH/entware" ] && mkdir -v "$TARGET_PATH/entware"
        mount --bind "$TARGET_PATH/entware" /opt && echo "Mounted $TARGET_PATH/entware on /opt"

        for DIR in bin etc lib/opkg tmp var/lock; do
            if [ ! -d "/opt/$DIR" ]; then
                mkdir -pv /opt/$DIR
            fi
        done

        PATH=/opt/bin:/opt/sbin:/opt/usr/bin:$PATH

        echo "Installing package manager..."

        if [ ! -f /opt/bin/opkg ]; then
            curl -fsS "$INSTALL_URL/opkg" -o /opt/bin/opkg
            chmod 755 /opt/bin/opkg
            echo "'$INSTALL_URL/opkg' -> '/opt/bin/opkg'"
        fi

        if [ ! -f /opt/etc/opkg.conf ]; then
            if [ -f /jffs/entware/etc/opkg.conf ]; then
                ln -sv /jffs/entware/etc/opkg.conf /opt/etc/opkg.conf
            else
                curl -fsS "$INSTALL_URL/opkg.conf" -o /opt/etc/opkg.conf
                echo "'$INSTALL_URL/opkg.conf' -> '/opt/etc/opkg.conf'"

                [ "$BASE_URL" != "$DEFAULT_BASE_URL" ] && sed -i "s#$DEFAULT_BASE_URL:#$BASE_URL:#g" /opt/etc/opkg.conf
                [ "$USE_HTTPS" = true ] && sed -i 's/http:/https:/g' /opt/etc/opkg.conf
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

        for FILE in passwd group shells shadow gshadow; do
            if [ "$ALTERNATIVE" != true ] && [ -f "/etc/$FILE" ]; then
                ln -sfv "/etc/$FILE" "/opt/etc/$FILE"
            else
                [ -f "/opt/etc/$FILE.1" ] && cp -v "/opt/etc/$FILE.1" "/opt/etc/$FILE"
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
