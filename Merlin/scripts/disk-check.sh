#!/bin/sh
# Made by Jack'lul <jacklul.github.io>
#
# Automatically checks filesystems before mount
#
# Based on:
#  https://github.com/RMerl/asuswrt-merlin.ng/wiki/USB-Disk-Check-at-Boot-or-Hot-Plug-(improved-version)
#  https://github.com/decoderman/amtm/blob/master/amtm_modules/disk_check.mod
#

TZ=$(cat /etc/TZ); export TZ
CHKLOG=/var/log/fsck.log
CHKCMD=""
SCRIPT_NAME="$(basename "$0" .sh)"

log() {
	[ "$2" != "true" ] && printf "\n$(date) %s\n" "$1" >> $CHKLOG

	logger -t "$SCRIPT_NAME" "$1"
}

[ -z "$1" ] && { echo "No device specified"; exit 1; }

ntptimer=0
ntptimeout=60
while [ "$(nvram get ntp_ready)" = 0 ] && [ "$ntptimer" -lt "$ntptimeout" ]; do
	ntptimer=$((ntptimer+1))
	sleep 1
done

if [ "$ntptimer" -ge "$ntptimeout" ]; then
	log "NTP timeout (${ntptimeout}s) reached, time is not synchronized"
elif [ "$ntptimer" -gt "0" ]; then
	log "Waited ${ntptimer}s for NTP to sync date"
else
	printf "\n" >> $CHKLOG
fi

if [ -f "$CHKLOG" ] && [ "$(wc -c < $CHKLOG)" -gt "100000" ]; then
	sed -i '1,100d' "$CHKLOG"
	sed -i "1s/^/Truncated log file, size over 100KB, on $(date)\n\n/" "$CHKLOG"
	logger -t "$SCRIPT_NAME" "Truncated $CHKLOG - size over 100KB"
fi

case "$2" in
	"")
		log "Error reading device $1 - skipping check"
	;;
	ext2|ext3|ext4)
		CHKCMD="e2fsck -p"
	;;
	hfs|hfs+j|hfs+jx)
		if [ -x /usr/sbin/chkhfs ]; then
			CHKCMD="chkhfs -a -f"
		elif [ -x /usr/sbin/fsck_hfs ]; then
			CHKCMD="fsck_hfs -d -ay"
		else
			text="Unsupported filesystem '$2' on device $1 - skipping check"
			printf "$(date) %s\n" "$text" >> $CHKLOG
			logger -t "$SCRIPT_NAME" "$text"
		fi
	;;
	ntfs)
		if [ -x /usr/sbin/chkntfs ]; then
			CHKCMD="chkntfs -a -f"
		elif [ -x /usr/sbin/ntfsck ]; then
			CHKCMD="ntfsck -a"
		fi
	;;
	vfat)
		CHKCMD="fatfsck -a"
	;;
	unknown)
		log "Unknown filesystem on device $1 (e.g. exFAT) or no partition table (e.g. blank media) - skipping check"
	;;
	*)
		log "Unexpected filesystem type '$2' for $1 - skipping check"
	;;
esac

if [ "$CHKCMD" ]; then
	log "Running disk check with command '$CHKCMD' on $1"
	$CHKCMD "$1" >> $CHKLOG 2>&1
	log "Disk check finished on $1, check $CHKLOG for details" true
fi
