#!/bin/sh
# This script will execute e2fsck on provided block device
# Only ext2/3/4 filesystems are supported
#
# Usage: ./fsck.sh /dev/sda1 /dev/sda2
#        ./fsck.sh /dev/sda
#        ./fsck.sh /dev/sda1 all
#        ./fsck.sh all
#
# Passing 'all' as an argument will check all partitions of 
# the specified devices or all block devices if none specified.
#
# Run this script before anything else from:
#  /jffs/scripts/pre-mount (Merlin)
#  /jffs/scripts/usb-mount-script (asusware-usbmount)
#
# To use Entware's e2fsck, first install it to your storage with:
#  ./fsck.sh install /tmp/mnt/sda1
#

tag="$(basename "$0")"
[ -t 0 ] && interactive=true
stop_fsck="$(nvram get stop_fsck 2> /dev/null)"

logger_echo() {
    if [ -z "$interactive" ]; then
        logger -st "$tag" "$1"
    fi

    echo "$1"
}

get_base_device() {
    _device="$1"

    case "$_device" in
        /dev/nvme*n*p[0-9]*)
            echo "$_device" | sed 's/p[0-9][0-9]*$//'
        ;;
        /dev/mmcblk*p[0-9]*)
            echo "$_device" | sed 's/p[0-9][0-9]*$//'
        ;;
        /dev/[a-z]*[0-9]*)
            echo "$_device" | sed 's/[0-9][0-9]*$//'
        ;;
        *)
            echo "$_device"
        ;;
    esac
}

copy_e2fsck_entware() {
    [ -n "$entware_e2fsck" ] && return

    if [ -x /opt/sbin/e2fsck ]; then
        export PATH="/opt/sbin:$PATH"
        entware_e2fsck=true
    elif [ ! -d /tmp/e2fsck-entware ] && [ -d "$1/.e2fsck-entware" ]; then
        cp -a "$1/.e2fsck-entware" /tmp/e2fsck-entware
        export PATH="/tmp/e2fsck-entware/opt/sbin:$PATH"
        entware_e2fsck=true
    fi

    if [ -n "$entware_e2fsck" ]; then
        logger_echo "Using Entware's e2fsck"
        unset LD_PRELOAD
        unset LD_LIBRARY_PATH
    fi
}

trap_cleanup() {
    rm -fr /tmp/e2fsck-entware

    if [ -n "$unmounted" ]; then
        logger_echo "Restarting nasapps"
        service restart_nasapps
    fi
}

run_fsck() {
    _device="$1"
    _mount="$(cat /proc/mounts | grep "^$_device " | head -n 1)"

    if [ -n "$_mount" ]; then
        # Only check ext* filesystems
        _fstype="$(echo "$_mount" | awk '{print $3}')"
        case "$_fstype" in
            ext2|ext3|ext4)
                # Filesystems other than ext4 are checked by the firmware already
                # Unless firmware's fsck script has been disabled with stop_fsck=1
                if [ "$stop_fsck" != "1" ] && [ "$_fstype" != "ext4" ]; then
                    return 1 # skip
                fi
            ;;
            *) return 1 ;; # unsupported filesystem
        esac

        # Save mountpoint path and options
        _mountpoint="$(echo "$_mount" | awk '{print $2}')"
        _options="$(echo "$_mount" | awk '{print $4}')"

        # Copy Entware's e2fsck if available
        copy_e2fsck_entware "$_mountpoint"
    fi

    logger_echo "Starting filesystem check on $_device"

    if [ -n "$_mount" ]; then
        # Wait for the mountpoint to become idle
        _timer=30
        while lsof | grep -Fq "$_mountpoint" && [ "$_timer" -gt 0 ] ; do
            _timer=$((_timer-1))
            sleep 1
        done
    fi

    # Unmount the device
    if [ -n "$_mountpoint" ] && ! umount "$_mountpoint"; then
        logger_echo "Failed to unmount $_device from $_mountpoint"
        return 1
    fi

    # Run e2fsck
    unmounted=true # so we can know to restart nasapps later
    _output="$(e2fsck -p -v "$_device" 2>&1)"
    _result=$?
    _log="/tmp/fsck_$(basename "$_device").log"

    #shellcheck disable=SC3037
    echo -e "$(type e2fsck 2>&1)\n$_output" > "$_log"
    logger_echo "Filesystem check $([ "$_result" -eq 0 ] && echo "succeeded" || echo "failed") on $_device - see '$_log' for details"

    # Remount under the same path and with the same options
    if [ -n "$_mountpoint" ] && ! mount -o "$_options" "$_device" "$_mountpoint"; then
        logger_echo "Failed to remount $_device on $_mountpoint ($_options)"
        return 1
    fi

    return $_result
}

case "$1" in
    install|update)
        type opkg >/dev/null 2>&1 || { logger_echo "Entware is not installed"; exit 1; }

        target_dir="$2"
        if [ -z "$target_dir" ]; then
            for dir in /tmp/mnt/*; do
                if [ -d "$dir" ] && mount | grep -F "/dev" | grep -Fq "$dir"; then
                    target_dir="$dir"
                    break
                fi
            done
        fi

        echo "Using storage: $target_dir"

        set -e
        case "$1" in
            install)
                [ -d "$target_dir/.e2fsck-entware" ] && { echo "e2fsck-entware is already installed in $target_dir/.e2fsck-entware"; exit 0; }

                #shellcheck disable=SC3045,SC2162
                read -p "Press any key to continue or CTRL-C to cancel... " -n1

                mkdir -p "$target_dir/.e2fsck-entware/opt/tmp" # need to create opt path for opkg to work
                opkg -f /opt/etc/opkg.conf -o "$target_dir/.e2fsck-entware" update
                opkg -f /opt/etc/opkg.conf -o "$target_dir/.e2fsck-entware" install e2fsprogs
            ;;
            update)
                [ ! -f "$target_dir/.e2fsck-entware/opt/sbin/e2fsck" ] && { echo "e2fsck-entware is not installed in $target_dir/.e2fsck-entware"; exit 0; }

                opkg -f /opt/etc/opkg.conf -o "$target_dir/.e2fsck-entware" update
                opkg -f /opt/etc/opkg.conf -o "$target_dir/.e2fsck-entware" upgrade
            ;;
        esac

        echo "Completed successfully"
        exit 0
    ;;
    *)
        [ -z "$1" ] && { logger_echo "Usage: $0 <block-device>|install|update [target-dir]"; exit 1; }

        devices=
        all=false
        while [ $# -gt 0 ]; do
            #shellcheck disable=SC2174
            case "$1" in
                all) 
                    all=true
                    shift
                ;;
                *) 
                    if [ -b "$1" ]; then
                        devices="$devices $1"
                    else
                        logger_echo "Not a block device: $1"
                    fi

                    shift
                ;;
            esac
        done

        trap trap_cleanup EXIT HUP INT TERM

        if [ -n "$devices" ]; then
            for device in $devices; do
                case "$device" in
                    /dev/sd*[0-9]|/dev/nvme*n*p[0-9]|/dev/mmcblk*p[0-9]) # exact partition number given
                        if [ "$all" != true ]; then
                            run_fsck "$device"
                            continue
                        else
                            device="$(get_base_device "$device")"
                            [ -z "$device" ] && { logger_echo "Failed to determine base device for: $device"; continue; }
                            [ ! -b "$device" ] && { logger_echo "Invalid base block device: $device"; continue; }
                        fi
                    ;;
                esac

                case "$device" in
                    /dev/sd*)
                        for partition in "$device"[0-9]*; do
                            [ -b "$partition" ] && run_fsck "$partition"
                        done
                    ;;
                    /dev/nvme*n*|/dev/mmcblk*)
                        for partition in "$device"p[0-9]*; do
                            [ -b "$partition" ] && run_fsck "$partition"
                        done
                    ;;
                    *)
                        logger_echo "Unsupported device type: $device"
                    ;;
                esac
            done
        elif [ "$all" = true ]; then
            for device in /dev/*; do
                [ -b "$device" ] || continue

                case "$device" in
                    /dev/sd*[0-9]|/dev/nvme*n*p[0-9]|/dev/mmcblk*p[0-9])
                        run_fsck "$device"
                    ;;
                esac
            done
        fi
    ;;
esac
