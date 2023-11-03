#!/bin/sh
# Made by Jack'lul <jacklul.github.io>
#
# Install and enable Entware
#
# Based on:
#  https://bin.entware.net/armv7sf-k3.2/installer/generic.sh
#  https://raw.githubusercontent.com/RMerl/asuswrt-merlin.ng/a46283c8cbf2cdd62d8bda231c7a79f5a2d3b889/release/src/router/others/entware-setup.sh
#

#shellcheck disable=SC2155,SC2016

readonly SCRIPT_PATH="$(readlink -f "$0")"
readonly SCRIPT_NAME="$(basename "$SCRIPT_PATH" .sh)"
readonly SCRIPT_DIR="$(dirname "$SCRIPT_PATH")"
readonly SCRIPT_CONFIG="$SCRIPT_DIR/$SCRIPT_NAME.conf"
readonly SCRIPT_TAG="$(basename "$SCRIPT_PATH")"

IN_RAM="" # Install Entware and packages in RAM (/tmp), space separated list
ARCHITECTURE="" # Entware architecture, set it only when auto install (to /tmp) can't detect it properly
USE_HTTPS=false # retrieve files using HTTPS, applies to OPKG repository and installation downloads
WAIT_LIMIT=60 # how many minutes to wait for auto install before giving up
CACHE_FILE="/tmp/last_entware_device" # where to store last device Entware was mounted on

if [ -f "$SCRIPT_CONFIG" ]; then
    #shellcheck disable=SC1090
    . "$SCRIPT_CONFIG"
fi

LAST_ENTWARE_DEVICE=""
[ -f "$CACHE_FILE" ] && LAST_ENTWARE_DEVICE="$(cat "$CACHE_FILE")"
CHECK_URL="http://bin.entware.net"
[ "$USE_HTTPS" = true ] && CHECK_URL="$(echo "$CHECK_URL" | sed 's/http:/https:/')"

lockfile() { #LOCKFILE_START#
    _LOCKFILE="/var/lock/script-$SCRIPT_NAME.lock"
    _PIDFILE="/var/run/script-$SCRIPT_NAME.pid"
    _FD=9

    if [ -n "$2" ]; then
        _LOCKFILE="/var/lock/script-$SCRIPT_NAME-$2.lock"
        _PIDFILE="/var/run/script-$SCRIPT_NAME-$2.lock"
    fi

    [ -n "$3" ] && [ "$3" -eq "$3" ] && _FD="$3"

    _LOCKPID=
    [ -f "$_PIDFILE" ] && _LOCKPID="$(cat "$_PIDFILE")"

    case "$1" in
        "lockwait"|"lockfail"|"lockexit")
            eval exec "$_FD>$_LOCKFILE"

            case "$1" in
                "lockwait"|"lock")
                    flock -x "$_FD"
                ;;
                "lockfail")
                    [ -n "$_LOCKPID" ] && [ -f "/proc/$_LOCKPID/stat" ] && return 1
                    flock -x "$_FD"
                ;;
                "lockexit")
                    [ -n "$_LOCKPID" ] && [ -f "/proc/$_LOCKPID/stat" ] && exit 1
                    flock -x "$_FD"
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
        [ "$_PPID" -gt "1" ] || break
    done

    return 1
} #STARTEDBYSYSTEMFUNC_END#

is_entware_mounted() {
    if mount | grep -q "on /opt "; then
        return 0
    else
        return 1
    fi
}

init_opt() {
    [ -z "$1" ] && { echo "Target path not provided"; exit 1; }

    if [ -f "$1/etc/init.d/rc.unslung" ]; then
        if is_entware_mounted && ! umount /opt; then
            logger -st "$SCRIPT_TAG" "Failed to unmount /opt"
            exit 1
        fi

        if mount --bind "$1" /opt; then
            MOUNT_DEVICE="$(mount | grep "on /opt " | tail -n 1 | awk '{print $1}')"
            [ -n "$MOUNT_DEVICE" ] && basename "$MOUNT_DEVICE" > "$CACHE_FILE"

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

backup_initd_scripts() {
    [ ! -d /opt/etc/init.d ] && return

    if [ -d "/tmp/$SCRIPT_NAME-init.d-backup" ]; then
        rm -rf "/tmp/$SCRIPT_NAME-init.d-backup/*"
    else
        mkdir -p "/tmp/$SCRIPT_NAME-init.d-backup"
    fi

    cp -f /opt/etc/init.d/rc.func "/tmp/$SCRIPT_NAME-init.d-backup"

    for FILE in /opt/etc/init.d/*; do
        [ ! -x "$FILE" ] && continue
        [ "$(basename "$FILE")" = "rc.unslung" ] && continue
        cp -f "$FILE" "/tmp/$SCRIPT_NAME-init.d-backup/$FILE"
        sed "s#/opt/etc/init.d/rc.func#/tmp/$SCRIPT_NAME-init.d-backup/rc.func#g" -i "/tmp/$SCRIPT_NAME-init.d-backup/$FILE"
    done
}

services() {
    case "$1" in
        "start")
            if is_entware_mounted; then
                if [ -f /opt/etc/init.d/rc.unslung ]; then
                    logger -st "$SCRIPT_TAG" "Starting services..."

                    /opt/etc/init.d/rc.unslung start "$SCRIPT_PATH"

                    [ -z "$IN_RAM" ] && backup_initd_scripts
                else
                    logger -st "$SCRIPT_TAG" "Entware is not installed"
                fi
            else
                logger -st "$SCRIPT_TAG" "Entware is not mounted"
            fi
        ;;
        "stop")
            if [ -f /opt/etc/init.d/rc.unslung ]; then
                logger -st "$SCRIPT_TAG" "Stopping services..."

                /opt/etc/init.d/rc.unslung stop "$SCRIPT_PATH"
            elif [ -d "/tmp/$SCRIPT_NAME-init.d-backup" ]; then
                logger -st "$SCRIPT_TAG" "Killing services..."

                for FILE in "/tmp/$SCRIPT_NAME-init.d-backup/"*; do
                    [ ! -x "$FILE" ] && continue
                    eval "$FILE kill"
                done

                rm -rf "/tmp/$SCRIPT_NAME-init.d-backup"
            fi
        ;;
    esac
}

entware_in_ram() {
    { [ "$(nvram get wan0_state_t)" != "2" ] && [ "$(nvram get wan1_state_t)" != "2" ]; } && { echo "WAN network is not connected"; return 1; }
    curl -fs "$CHECK_URL" > /dev/null || { echo "Cannot reach entware.net server"; return 1; }

    lockfile lockwait

    if [ ! -f /opt/etc/init.d/rc.unslung ]; then # is it not mounted?
        if [ ! -f /tmp/entware/etc/init.d/rc.unslung ]; then # is it not installed?
            logger -st "$SCRIPT_TAG" "Installing Entware in /tmp/entware..."

            if ! sh "$SCRIPT_PATH" install /tmp > /tmp/entware-install.log 2>&1; then
                logger -st "$SCRIPT_TAG" "Installation failed, check /tmp/entware-install.log for details"
                cru d "$SCRIPT_NAME"
                return 1
            fi

            logger -st "$SCRIPT_TAG" "Installation successful"
        fi

        ! is_entware_mounted && init_opt /tmp/entware
        services start
    fi

    lockfile unlock

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

            if is_entware_mounted && ! umount /opt; then
                logger -st "$SCRIPT_TAG" "Failed to unmount /opt"
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
            if is_started_by_system && [ "$2" != "nohup" ]; then
                lockfile check && exit

                nohup "$SCRIPT_PATH" run nohup > /dev/null 2>&1 &
            else
                lockfile lockfail "inram" 8 || { echo "Already running! ($_LOCKPID)"; exit 1; }

                LIMIT="$WAIT_LIMIT"
                while true; do
                    [ -f /opt/etc/init.d/rc.unslung ] && break
                    entware_in_ram && break

                    LIMIT=$((LIMIT-1))
                    [ "$LIMIT" -le "0" ] && break

                    sleep 60
                done
                [ "$LIMIT" -le "0" ] && logger -st "$SCRIPT_TAG" "Failed to start Entware installation (tried for $WAIT_LIMIT minutes) - network connection could not be established"

                lockfile unlock "inram" 8
            fi

            exit
        fi

        if ! is_entware_mounted; then
            for DIR in /tmp/mnt/*; do
                if [ -d "$DIR/entware" ]; then
                    entware start "$DIR/entware"

                    break
                fi
            done
        else
            [ -z "$LAST_ENTWARE_DEVICE" ] && exit
            [ -z "$IN_RAM" ] && backup_initd_scripts

            TARGET_PATH="$(mount | grep "$LAST_ENTWARE_DEVICE" | head -n 1 | awk '{print $3}')"

            if [ -z "$TARGET_PATH" ]; then
                entware stop
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
        [ -z "$IN_RAM" ] && cru a "$SCRIPT_NAME" "*/1 * * * * $SCRIPT_PATH run"

        sh "$SCRIPT_PATH" run
    ;;
    "stop")
        cru d "$SCRIPT_NAME"

        entware stop
        lockfile kill "inram" 8
    ;;
    "restart")
        sh "$SCRIPT_PATH" stop
        sh "$SCRIPT_PATH" start
    ;;
    "install")
        is_entware_mounted && { echo "Entware seems to be already mounted - unmount it before continuing"; exit 1; }

        [ -z "$IN_RAM" ] && echo

        TARGET_PATH="$2"
        [ -z "$ARCHITECTURE" ] && ARCHITECTURE="$3"

        if [ -z "$TARGET_PATH" ]; then
            for DIR in /tmp/mnt/*; do
                if [ -d "$DIR" ] && mount | grep "/dev" | grep -q "$DIR"; then
                    TARGET_PATH="$DIR"
                    break
                fi
            done

            [ -z "$TARGET_PATH" ] && { echo "Target path not provided"; exit 1; }

            echo "Detected mounted storage: $TARGET_PATH"
            echo "You can override it by providing it as the second argument."
            echo
        fi

        [ ! -d "$TARGET_PATH" ] && { echo "Target path does not exist: $TARGET_PATH"; exit 1; }
        [ -f "$TARGET_PATH/entware/etc/init.d/rc.unslung" ] && { echo "Entware seems to be already installed in $TARGET_PATH/entware"; exit; }

        if [ -z "$ARCHITECTURE" ]; then
            PLATFORM=$(uname -m)
            KERNEL=$(uname -r)

            case $PLATFORM in
                "armv7l")
                    ARCHITECTURE="armv7sf-k2.6"

                    if [ "$(echo "$KERNEL" | cut -d'.' -f1)" -gt 2 ]; then
                        ARCHITECTURE="armv7sf-k3.2"
                    fi
                ;;
                "aarch64")
                    ARCHITECTURE="aarch64-k3.10"
                ;;
                *)
                    echo "Unsupported platform or failed to detect - provide supported architecture as the third argument."
                    echo "Check https://bin.entware.net or https://pkg.entware.net/binaries/ for supported ones."
                    exit 1
                ;;
            esac

            if [ -z "$IN_RAM" ]; then
                echo "Detected architecture: $ARCHITECTURE"
                echo "You can override it by providing it as the third argument."
                echo
            fi
        fi

        case "$ARCHITECTURE" in
            "aarch64-k3.10"|"armv5sf-k3.2"|"armv7sf-k2.6"|"armv7sf-k3.2"|"mipselsf-k3.4"|"mipssf-k3.4"|"x64-k3.2"|"x86-k2.6")
                INSTALL_URL="http://bin.entware.net/$ARCHITECTURE/installer"
            ;;
            "mips"|"mipsel"|"armv5"|"armv7"|"x86-32"|"x86-64")
                INSTALL_URL="http://pkg.entware.net/binaries/$ARCHITECTURE/installer"
            ;;
            *)
                echo "Unsupported architecture: $ARCHITECTURE";
                exit 1;
            ;;
        esac

        [ "$USE_HTTPS" = true ] && INSTALL_URL="$(echo "$INSTALL_URL" | sed 's/http:/https:/')"

        echo "Will install Entware on $TARGET_PATH from $INSTALL_URL"

        if [ -z "$IN_RAM" ]; then
            #shellcheck disable=SC3045,SC2162
            read -p "Press any key to continue or CTRL-C to cancel... "
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

        chmod 777 /opt/tmp
        PATH=/opt/bin:/opt/sbin:$PATH

        echo "Installing package manager..."

        if [ ! -f /opt/bin/opkg ]; then
            curl -fs "$INSTALL_URL/opkg" -o /opt/bin/opkg && chmod 755 /opt/bin/opkg
        fi

        if [ ! -f /opt/etc/opkg.conf ]; then
            curl -fs "$INSTALL_URL/opkg.conf" -o /opt/etc/opkg.conf
            [ "$USE_HTTPS" = true ] && sed -i 's/http:/https:/g' /opt/etc/opkg.conf
        fi

        echo "Installing core packages..."

        opkg update
        opkg install entware-opt

        echo "Checking and copying required files..."

        for FILE in passwd group shells shadow gshadow; do
            if [ -f "/etc/$FILE" ]; then
                ln -sfv "/etc/$FILE" "/opt/etc/$FILE"
            else
                [ -f "/opt/etc/$FILE.1" ] && cp -v "/opt/etc/$FILE.1" "/opt/etc/$FILE"
            fi
        done

        [ -f /etc/localtime ] && ln -sfv /etc/localtime /opt/etc/localtime

        echo "Modifying /opt/etc/init.d/rc.* scripts..."
        ! grep -q "CALLER=unknown" /opt/etc/init.d/rc.func && sed -i '/CALLER=$2/a[ -z "$CALLER" ] && CALLER=unknown' /opt/etc/init.d/rc.func
        ! grep -q "CALLER=unknown" /opt/etc/init.d/rc.unslung && sed -i '/CALLER=$2/a[ -z "$CALLER" ] && CALLER=unknown' /opt/etc/init.d/rc.unslung

        if [ -n "$IN_RAM" ]; then
            if [ -d /jffs/entware ] && [ -n "$(ls -A /jffs/entware)" ]; then
                echo "Symlinking data from /jffs/entware..."

                find /jffs/entware -type f -exec sh -c '
                    TARGET_FILE="$(echo "$1" | sed "s@/jffs/entware@/opt@")"
                    TARGET_DIR="$(dirname "$TARGET_FILE")"

                    TEST_DIR="$(dirname "$1")"
                    LIMIT=10
                    while [ "$LIMIT" -gt "0" ]; do
                        [ -f "$TEST_DIR/.symlinkthisdir" ] && exit
                        TEST_DIR="$(dirname "$TEST_DIR")"
                        [ "$TEST_DIR" = "/jffs/entware" ] && break
                        LIMIT=$((LIMIT-1))
                    done

                    if [ -f "$TARGET_FILE" ]; then
                        echo "Warning: File $TARGET_FILE already exists, renaming..."
                        mv -v "$TARGET_FILE" "$TARGET_FILE.bak_$(date +%s)"
                    fi

                    [ ! -d "$TARGET_DIR" ] && mkdir -pv "$TARGET_DIR"
                    ln -sv "$1" "$TARGET_FILE" || echo "Failed to create a symlink: $TARGET_FILE => $1"
                ' sh {} \;

                find /jffs/entware -type d -exec sh -c '
                    [ ! -f "$1/.symlinkthisdir" ] && exit

                    TARGET_DIR="$(echo "$1" | sed "s@/jffs/entware@/opt@")"
                    TARGET_DIR_DIR="$(dirname "$TARGET_DIR")"

                    if [ -d "$TARGET_DIR" ]; then
                        echo "Warning: Directory $TARGET_DIR already exists, renaming..."
                        mv -v "$TARGET_DIR" "$TARGET_DIR.bak_$(date +%s)"
                    fi

                    [ ! -d "$TARGET_DIR_DIR" ] && mkdir -pv "$TARGET_DIR_DIR"
                    ln -sv "$1" "$TARGET_DIR" || echo "Failed to create a symlink: $TARGET_DIR => $1"
                ' sh {} \;
            fi

            echo "Installing selected packages..."

            #shellcheck disable=SC2086
            opkg install $IN_RAM
        fi

        echo "Installation complete!"
    ;;
    *)
        echo "Usage: $0 run|start|stop|restart|install"
        exit 1
    ;;
esac
