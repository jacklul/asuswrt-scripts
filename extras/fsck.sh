#!/bin/sh
# This script will execute fsck on provided block device
# Only ext2/3/4 filesystems are supported
#
# Usage: ./fsck.sh /dev/sda1
#
# Run it before anything else from:
#  /jffs/scripts/pre-mount (Merlin)
#  /jffs/scripts/usb-mount-script (asusware-usbmount)
#

tag="$(basename "$0")"
unmounted= # used at the bottom of the script

#########################

# If this is 1 then we can run fsck on ext2 and ext3, otherwise handled by firmware
stop_fsck="$(nvram get stop_fsck 2>/dev/null)"

check_filesystem() {
    _device="$1"
    _mount="$(cat /proc/mounts | grep "^$_device " | head -n 1)"

    [ -z "$_mount" ] && return 1 # not mounted

    # Only check ext* filesystems
    _fstype="$(echo "$_mount" | awk '{print $3}')"
    case "$_fstype" in
        ext2|ext3|ext4) ;;
        *)
            logger -st "$tag" "Unsupported filesystem '$_fstype' on $_device"
            return 1
        ;;
    esac

    # Filesystems other than ext4 are checked by the firmware already
    # Unless firmware's fsck script has been disabled with stop_fsck=1
    if [ "$_fstype" != "ext4" ] && [ "$stop_fsck" != "1" ]; then
        return 1
    fi

    logger -st "$tag" "Running filesystem check on $_device ($_mountpoint)"

    # Get mountpoint of the device
    _mountpoint="$(echo "$_mount" | awk '{print $2}')"

    # Wait for the mountpoint to become idle
    _timer=60
    while lsof | grep -Fq "$_mountpoint" && [ "$_timer" -gt 0 ] ; do
        _timer=$((_timer-1))
        sleep 1
    done

    # Save current mount options for later remount
    _options="$(echo "$_mount" | awk '{print $4}')"

    # Unmount the device
    if ! umount "$_mountpoint"; then
        logger -st "$tag" "Failed to unmount $_device from $_mountpoint"
        return 1
    fi

    unmounted=true
    _basename="$(basename "$_device")"

    # Use firmware's app_fsck.sh script when available
    if [ -f /usr/sbin/app_fsck.sh ]; then
        /usr/sbin/app_fsck.sh "$_fstype" "$_device"
        ret_dir=/tmp/fsck_ret
        [ -f "$ret_dir/$_basename.0" ] && _result=0 || _result=1
        _log="$ret_dir/$_basename.log"
    else # ...otherwise just execute fsck
        _output="$("fsck.$_fstype" -p -v "$_device" 2>&1)"
        _result=$?
        _log="/tmp/fsck_$_basename.log"
        #shellcheck disable=SC3037
        echo -e "$_output" > "$_log"
    fi

    _return=0

    if [ "$_result" -eq 0 ]; then
        logger -st "$tag" "Filesystem check succeeded on $_device"
    else
        logger -st "$tag" "Filesystem check failed on $_device - see $_log for details"
        _return=1 # cannot return here, need to remount first
    fi

    # Remount under the same path and with the same options
    if ! mount -o "$_options" "$_device" "$_mountpoint"; then
        logger -st "$tag" "Failed to remount $_device on $_mountpoint ($_options)"
        return 1
    fi

    return $_return
}

#########################

if [ -n "$1" ]; then
    if [ -b "$1" ]; then # make sure it is a block device
        case "$1" in
            /dev/sd*[0-9]|/dev/nvme*n*p[0-9]|/dev/mmcblk*p[0-9]) # exact partition number was provided
                check_filesystem "$1"
            ;;
            *) # only base device was provided - check all mounted partitions on it
                case "$1" in
                    /dev/sd*)
                        for partition in "$1"[0-9]*; do
                            if [ -b "$partition" ]; then
                                check_filesystem "$partition"
                            fi
                        done
                    ;;
                    /dev/nvme*n*|/dev/mmcblk*)
                        for partition in "$1"p[0-9]*; do
                            if [ -b "$partition" ]; then
                                check_filesystem "$partition"
                            fi
                        done
                    ;;
                    *)
                        logger -st "$tag" "Unsupported device type: $1"
                    ;;
                esac
            ;;
        esac
    elif [ "$1" = "all" ]; then # alternative - check every mounted partition
        for device in /dev/*; do
            [ -b "$1" ] || continue

            case "$device" in
                /dev/sd*|/dev/nvme*n*|/dev/mmcblk*)
                    check_filesystem "$device"
                ;;
            esac
        done
    else
        logger -st "$tag" "Invalid device: $1"
    fi
fi

# Restart storage related services
if [ -n "$unmounted" ]; then
    service restart_nasapps
fi
