#!/bin/sh
# Made by Jack'lul <jacklul.github.io>
#
# Setup and enable swap file on startup
#
# Based on:
#  https://github.com/decoderman/amtm/blob/master/amtm_modules/swap.mod
#

#shellcheck disable=SC2155

SWAP_FILE="" # swap file path, like "/tmp/mnt/USBDEVICE/swap.img"
SWAP_SIZE=128000 # swap file size, changing after swap is created requires it to be manually removed, 128000 = 128MB

# This means that this is a Merlin firmware
if [ -f "/usr/sbin/helper.sh" ]; then
    #shellcheck disable=SC1091
    . /usr/sbin/helper.sh

    SWAP_FILE_=$(am_settings_get jl_swap_file)
    SWAP_SIZE_=$(am_settings_get jl_swap_size)

    [ -n "$SWAP_FILE_" ] && SWAP_FILE=$SWAP_FILE_
    [ -n "$SWAP_SIZE_" ] && SWAP_SIZE=$SWAP_SIZE_
fi

readonly SCRIPT_NAME="$(basename "$0" .sh)"
readonly SCRIPT_PATH="$(readlink -f "$0")"
readonly SCRIPT_CONFIG="$(dirname "$0")/$SCRIPT_NAME.conf"
if [ -f "$SCRIPT_CONFIG" ]; then
    #shellcheck disable=SC1090
    . "$SCRIPT_CONFIG"
fi

manage_swap() {
    [ ! -f "$SWAP_FILE" ] && { logger -s -t "$SCRIPT_NAME" "Swap path is not set"; exit 1; }

    case "$1" in
        "enable")
            if [ "$(nvram get usb_idle_timeout)" != "0" ]; then
                logger -s -t "$SCRIPT_PATH" "Unable to enable swap - USB Idle timeout is set"
            else
                if swapon "$SWAP_FILE" ; then
                    #shellcheck disable=SC2012
                    logger -s -t "$SCRIPT_PATH" "Enabled swap on $SWAP_FILE ($(ls -hs "$SWAP_FILE" | awk '{print $1}'))"
                else
                    logger -s -t "$SCRIPT_PATH" "Failed to enable swap on $SWAP_FILE"
                fi
            fi
        ;;
        "disable")
            sync
            echo 3 > /proc/sys/vm/drop_caches
        
            if swapoff "$SWAP_FILE" ; then
                logger -s -t "$SCRIPT_PATH" "Disabled swap on $SWAP_FILE"
            else
                logger -s -t "$SCRIPT_PATH" "Failed to disable swap on $SWAP_FILE"
            fi
        ;;
        "create")
            set -e
            
            [ -z "$SWAP_SIZE" ] && { logger -s -t "$SCRIPT_NAME" "Swap size is not set"; exit 1; }
            
            logger -s -t "$SCRIPT_NAME" "Creating swap file..."
            
            touch "$SWAP_FILE"
            chattr -f +C "$SWAP_FILE" || true
            dd if=/dev/zero of="$SWAP_FILE" bs=1k count="$SWAP_SIZE"

            mkswap "$SWAP_FILE"
            chown root:root "$SWAP_FILE"
            chmod 0600 "$SWAP_FILE"

            set +e
        ;;
    esac
}

case "$1" in
    "create_and_start")
        manage_swap create
        manage_swap enable
    ;;
    "start")
        if [ -d "$(dirname "$SWAP_FILE")" ] && [ ! -f "$SWAP_FILE" ]; then
            sh "$SCRIPT_PATH" create_and_start &
            exit
        fi
        
        manage_swap enable
    ;;
    "stop")
        manage_swap disable
    ;;
    *)
        echo "Usage: $0 start|stop"
        exit 1
    ;;
esac
