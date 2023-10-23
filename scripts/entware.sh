#!/bin/sh
# Made by Jack'lul <jacklul.github.io>
#
# Install and enable Entware
#

#shellcheck disable=SC2155

readonly SCRIPT_PATH="$(readlink -f "$0")"
readonly SCRIPT_NAME="$(basename "$SCRIPT_PATH" .sh)"
readonly SCRIPT_DIR="$(dirname "$SCRIPT_PATH")"
readonly SCRIPT_CONFIG="$SCRIPT_DIR/$SCRIPT_NAME.conf"
readonly SCRIPT_TAG="$(basename "$SCRIPT_PATH")"

TARGET_PATH="" # target mount path (/tmp/mnt/XXX), when left empty will search for mount that has "entware" directory
ARCHITECTURE="armv7sf-k3.2" # must be set to matching architecture of your router (uname -a), must be one of supported ones on https://bin.entware.net

if [ -f "$SCRIPT_CONFIG" ]; then
    #shellcheck disable=SC1090
    . "$SCRIPT_CONFIG"
fi

if [ -z "$TARGET_PATH" ]; then
    for DIR in /tmp/mnt/*; do
        if [ -d "$DIR/entware" ]; then
            TARGET_PATH="$DIR"
            break
        fi
    done
fi

log_or_echo() {
    TEXT="$1"

    if [ -n "$INSTALL" ]; then
        echo "$TEXT"
    else
        logger -s -t "$SCRIPT_TAG" "$TEXT"
    fi
}

init_opt() {
    if [ -d "$TARGET_PATH/entware" ]; then
        if mount | grep -q "on /opt " && ! umount /opt; then
            log_or_echo "Failed to unmount /opt"
            exit 1
        fi

        mount --bind "$TARGET_PATH/entware" /opt && log_or_echo "Mounted $TARGET_PATH/entware on /opt"
    else
        log_or_echo "Entware directory $TARGET_PATH/entware does not exist"
        exit 22
    fi
}

entware() {
    case "$1" in
        "start")
            if ! mount | grep -q "on /opt "; then
                init_opt

                if [ -f "/opt/etc/init.d/rc.unslung" ]; then
                    logger -s -t "$SCRIPT_TAG" "Starting Entware..."
                    /opt/etc/init.d/rc.unslung start
                else
                    logger -s -t "$SCRIPT_TAG" "Entware is not installed"
                fi
            else
                logger -s -t "$SCRIPT_TAG" "Entware is already started"
            fi
        ;;
        "stop")
            if [ -f "/opt/etc/init.d/rc.unslung" ]; then
                logger -s -t "$SCRIPT_TAG" "Stopping Entware..."
                /opt/etc/init.d/rc.unslung stop
            fi

            if  mount | grep -q "on /opt "; then
                umount /opt || cru a "$SCRIPT_NAME-unmount" "*/1 * * * * $SCRIPT_PATH unmount"
            fi
        ;;
    esac
}

case "$1" in
    "install")
        [ -z "$TARGET_PATH" ] && { echo "Target path is not set"; exit 22; }
        [ ! -d "$TARGET_PATH" ] && { echo "Target path does not exist"; exit 22; }
        
        set -e
        INSTALL=true

        echo 'Checking and creating required directories...'

        if [ -d "$TARGET_PATH/entware" ]; then
            if [ -f "/opt/etc/localtime" ]; then
                echo "Entware seems to be already installed in $TARGET_PATH/entware"
                exit 1
            fi
        else
            mkdir "$TARGET_PATH/entware"
        fi

        init_opt

        for DIR in bin etc lib/opkg tmp var/lock; do
            if [ ! -d "/opt/$DIR" ]; then
                echo "Creating /opt/$DIR..."
                mkdir -p /opt/$DIR
            fi
        done

        chmod 777 /opt/tmp

        case "$ARCHITECTURE" in
            "aarch64-k3.10"|"armv5sf-k3.2"|"armv7sf-k2.6"|"armv7sf-k3.2"|"mipselsf-k3.4"|"mipssf-k3.4"|"x64-k3.2"|"x86-k2.6")
                INSTALL_URL="https://bin.entware.net/$ARCHITECTURE/installer"
            ;;
            *)
                echo "Unsupported architecture: $ARCHITECTURE";
                exit 1;
            ;;
        esac

        if [ ! -f "/opt/bin/opkg" ]; then
            wget "$INSTALL_URL/opkg" -O /opt/bin/opkg
            chmod 755 /opt/bin/opkg
        fi

        if [ ! -f "/opt/etc/opkg.conf" ]; then
            wget "$INSTALL_URL/opkg.conf" -O /opt/etc/opkg.conf
        fi

        echo 'Basic packages installation...'

        /opt/bin/opkg update
        /opt/bin/opkg install entware-opt

        echo 'Checking and copying required files...'

        for FILE in passwd group shells shadow gshadow; do
            if [ -f "/etc/$FILE" ]; then
                ln -sf "/etc/$FILE" "/opt/etc/$FILE"
            else
                [ -f "/opt/etc/$FILE.1" ] && cp "/opt/etc/$FILE.1" "/opt/etc/$FILE"
            fi
        done

        [ -f "/etc/localtime" ] && ln -sf "/etc/localtime" "/opt/etc/localtime"

        echo 'Installation complete!'
    ;;
    "hotplug")
        if [ "$(echo "$DEVICENAME" | cut -c 1-2)" = "sd" ]; then
            sh "$SCRIPT_PATH" run
        fi
    ;;
    "run")
        if [ -d "$TARGET_PATH/entware" ]; then
            if ! mount | grep -q "on /opt "; then
                entware start
            fi
        else
            entware stop
        fi
    ;;
    "unmount")
        if mount | grep -q "on /opt "; then
            umount /opt && cru d "$SCRIPT_NAME-unmount"
        else
            cru d "$SCRIPT_NAME-unmount"
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
    *)
        echo "Usage: $0 run|start|stop|restart|install|unmount"
        exit 1
    ;;
esac
