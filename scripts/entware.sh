#!/bin/sh
# Made by Jack'lul <jacklul.github.io>
#
# Install and enable Entware
#
# Based on:
#  https://bin.entware.net/armv7sf-k3.2/installer/generic.sh
#  https://raw.githubusercontent.com/RMerl/asuswrt-merlin.ng/a46283c8cbf2cdd62d8bda231c7a79f5a2d3b889/release/src/router/others/entware-setup.sh
#

#shellcheck disable=SC2155

readonly SCRIPT_PATH="$(readlink -f "$0")"
readonly SCRIPT_NAME="$(basename "$SCRIPT_PATH" .sh)"
readonly SCRIPT_DIR="$(dirname "$SCRIPT_PATH")"
readonly SCRIPT_CONFIG="$SCRIPT_DIR/$SCRIPT_NAME.conf"
readonly SCRIPT_TAG="$(basename "$SCRIPT_PATH")"

USE_HTTPS=true # retrieve files using HTTPS with OPKG, disable when downloads fails
CACHE_FILE="/tmp/last_entware_device" # where to store last device Entware was mounted on

if [ -f "$SCRIPT_CONFIG" ]; then
    #shellcheck disable=SC1090
    . "$SCRIPT_CONFIG"
fi

LAST_ENTWARE_DEVICE=""
[ -f "$CACHE_FILE" ] && LAST_ENTWARE_DEVICE="$(cat "$CACHE_FILE")"

lockfile() { #LOCKFUNC_START#
    _LOCKFILE="/tmp/$SCRIPT_NAME.lock"

    case "$1" in
        "lock")
            if [ -f "$_LOCKFILE" ]; then
                _LOCKWAITLIMIT=60
                _LOCKWAITTIMER=0
                while [ "$_LOCKWAITTIMER" -lt "$_LOCKWAITLIMIT" ]; do
                    [ ! -f "$_LOCKFILE" ] && break

                    _LOCKPID="$(sed -n '1p' "$_LOCKFILE")"
                    _LOCKCMD="$(sed -n '2p' "$_LOCKFILE")"

                    [ ! -d "/proc/$_LOCKPID" ] && break;
                    [ "$_LOCKPID" = "$$" ] && break;

                    _LOCKWAITTIMER=$((_LOCKWAITTIMER+1))
                    sleep 1
                done

                [ "$_LOCKWAITTIMER" -ge "$_LOCKWAITLIMIT" ] && { logger -st "$SCRIPT_TAG" "Unable to obtain lock after $_LOCKWAITLIMIT seconds, held by $_LOCKPID ($_LOCKCMD)"; exit 1; }
            fi

            echo "$$" > "$_LOCKFILE"
            echo "$@" >> "$_LOCKFILE"
            trap 'rm -f "$_LOCKFILE"; exit $?' EXIT
        ;;
        "unlock")
            if [ -f "$_LOCKFILE" ]; then
                _LOCKPID="$(sed -n '1p' "$_LOCKFILE")"

                if [ -d "/proc/$_LOCKPID" ] && [ "$_LOCKPID" != "$$" ]; then
                    echo "Attempted to remove not own lock"
                    exit 1
                fi

                rm -f "$_LOCKFILE"
            fi

            trap - EXIT
        ;;
    esac
} #LOCKFUNC_END#

is_entware_mounted() {
    if mount | grep -q "on /opt "; then
        return 0
    else
        return 1
    fi
}

init_opt() {
    _TARGET_PATH="$1"

    [ -z "$_TARGET_PATH" ] && { logger -st "$SCRIPT_TAG" "Target path not provided"; exit 1; }

    if [ -f "$_TARGET_PATH/etc/init.d/rc.unslung" ]; then
        if is_entware_mounted && ! umount /opt; then
            logger -st "$SCRIPT_TAG" "Failed to unmount /opt"
            exit 1
        fi

        if mount --bind "$_TARGET_PATH" /opt; then
            MOUNT_DEVICE="$(mount | grep "on /opt " | tail -n 1 | awk '{print $1}')"
            [ -n "$MOUNT_DEVICE" ] && basename "$MOUNT_DEVICE" > "$CACHE_FILE"

            logger -st "$SCRIPT_TAG" "Mounted $_TARGET_PATH on /opt"
        else
            logger -st "$SCRIPT_TAG" "Failed to mount $_TARGET_PATH on /opt"
            exit 1
        fi
    else
        logger -st "$SCRIPT_TAG" "Entware not found in $_TARGET_PATH"
        exit 1
    fi
}

backup_initd_scripts() {
    [ -d "/tmp/$SCRIPT_NAME/init.d" ] && rm -rf "/tmp/$SCRIPT_NAME/init.d"
    mkdir -p "/tmp/$SCRIPT_NAME/init.d"

    for FILE in /opt/etc/init.d/*; do
        [ ! -x "$FILE" ] && continue
        [ "$(basename "$FILE")" = "rc.unslung" ] && continue
        cp -f "$FILE" "/tmp/$SCRIPT_NAME/init.d/$FILE"
    done
}

services() {
    case "$1" in
        "start")
            if is_entware_mounted; then
                if [ -f "/opt/etc/init.d/rc.unslung" ]; then
                    logger -st "$SCRIPT_TAG" "Starting services..."

                    /opt/etc/init.d/rc.unslung start

                    backup_initd_scripts
                else
                    logger -st "$SCRIPT_TAG" "Entware is not installed"
                fi
            else
                logger -st "$SCRIPT_TAG" "Entware is not mounted"
            fi
        ;;
        "stop")
            if [ -f "/opt/etc/init.d/rc.unslung" ]; then
                logger -st "$SCRIPT_TAG" "Stopping services..."

                /opt/etc/init.d/rc.unslung stop
            elif [ -d "/tmp/$SCRIPT_NAME/init.d" ]; then
                logger -st "$SCRIPT_TAG" "Killing services..."

                for FILE in "/tmp/$SCRIPT_NAME/init.d/"*; do
                    [ ! -x "$FILE" ] && continue
                    eval "$FILE kill"
                done

                rm -rf "/tmp/$SCRIPT_NAME/init.d"
            fi
        ;;
    esac
}

entware() {
    lockfile lock

    case "$1" in
        "start")
            _ENTWARE_PATH="$2"
            [ -z "$_ENTWARE_PATH" ] && { logger -st "$SCRIPT_TAG" "Entware directory not provided"; exit 1; }

            [ -d "$_ENTWARE_PATH/entware" ] && TARGET_PATH="$_ENTWARE_PATH/entware"

            init_opt "$_ENTWARE_PATH"
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
        if ! is_entware_mounted; then
            for DIR in /tmp/mnt/*; do
                if [ -d "$DIR/entware" ]; then
                    entware start "$DIR/entware"

                    break
                fi
            done
        else
            [ -z "$LAST_ENTWARE_DEVICE" ] && exit

            TARGET_PATH="$(mount | grep "$LAST_ENTWARE_DEVICE" | head -n 1 | awk '{print $3}')"

            if [ -z "$TARGET_PATH" ]; then
                entware stop
            fi
        fi
    ;;
    "hotplug")
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
        cru a "$SCRIPT_NAME" "*/1 * * * * $SCRIPT_PATH run"

        sh "$SCRIPT_PATH" run
    ;;
    "stop")
        cru d "$SCRIPT_NAME"

        entware stop
    ;;
    "restart")
        sh "$SCRIPT_PATH" stop
        sh "$SCRIPT_PATH" start
    ;;
    "install")
        is_entware_mounted && { echo "Entware seems to be already mounted - unmount it before continuing"; exit 1; }

        echo

        TARGET_PATH="$2"
        ARCHITECTURE="$3"

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
                    echo "Check https://bin.entware.net or http://pkg.entware.net/binaries/ for supported ones."
                    exit 1
                ;;
            esac

            echo "Detected architecture: $ARCHITECTURE"
            echo "You can override it by providing it as the third argument."
            echo
        fi

        case "$ARCHITECTURE" in
            "aarch64-k3.10"|"armv5sf-k3.2"|"armv7sf-k2.6"|"armv7sf-k3.2"|"mipselsf-k3.4"|"mipssf-k3.4"|"x64-k3.2"|"x86-k2.6")
                INSTALL_URL="https://bin.entware.net/$ARCHITECTURE/installer"
            ;;
            "mips"|"mipsel"|"armv5"|"armv7"|"x86-32"|"x86-64")
                INSTALL_URL="http://pkg.entware.net/binaries/$ARCHITECTURE/installer"
            ;;
            *)
                echo "Unsupported architecture: $ARCHITECTURE";
                exit 1;
            ;;
        esac

        echo "Will install Entware from: $INSTALL_URL"

        #shellcheck disable=SC3045,SC2162
        read -p "Press any key to continue or CTRL-C to cancel... "

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

        if [ ! -f "/opt/bin/opkg" ]; then
            wget -nv "$INSTALL_URL/opkg" -O /opt/bin/opkg
            chmod 755 /opt/bin/opkg
        fi

        if [ ! -f "/opt/etc/opkg.conf" ]; then
            wget -nv "$INSTALL_URL/opkg.conf" -O /opt/etc/opkg.conf

            [ "$USE_HTTPS" = true ] && sed -i 's/http:/https:/g' /opt/etc/opkg.conf
        fi

        echo "Basic packages installation..."

        /opt/bin/opkg update
        /opt/bin/opkg install entware-opt

        echo "Checking and copying required files..."

        for FILE in passwd group shells shadow gshadow; do
            if [ -f "/etc/$FILE" ]; then
                ln -sfv "/etc/$FILE" "/opt/etc/$FILE"
            else
                [ -f "/opt/etc/$FILE.1" ] && cp -v "/opt/etc/$FILE.1" "/opt/etc/$FILE"
            fi
        done

        [ -f "/etc/localtime" ] && ln -sfv "/etc/localtime" "/opt/etc/localtime"

        echo "Installation complete!"
    ;;
    *)
        echo "Usage: $0 run|start|stop|restart|install"
        exit 1
    ;;
esac
