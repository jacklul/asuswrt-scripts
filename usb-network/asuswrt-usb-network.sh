#!/bin/bash
# Made by Jack'lul <jacklul.github.io>
#
# This script allows connecting Raspberry Pi to most
# Asus routers through USB networking gadget
#
# For more information, see:
# https://github.com/jacklul/asuswrt-usb-raspberry-pi
#

# shellcheck disable=2155,1090

[ "$UID" -eq 0 ] || { echo "This script must run as root!"; exit 1; }

# Configuration variables
NETWORK_FUNCTION="ecm"    # network function to use, supported: ecm (recommended), rndis, eem, ncm
VERIFY_CONNECTION=true    # verify that we can reach gateway after enabling network gadget
SKIP_MASS_STORAGE=false    # skip adding mass storage gadget, setup network gadget right away
VERIFY_TIMEOUT=60    # maximum seconds to wait for the connection check
VERIFY_SLEEP=1    # time to sleep between each gateway ping
WAIT_TIMEOUT=60    # maximum seconds to wait for the router to write to the storage image file
WAIT_SLEEP=1    # time to sleep between each image contents checks
TEMP_IMAGE_SIZE="1M"    # dd's bs parameter
TEMP_IMAGE_COUNT=1    # dd's count parameter
TEMP_IMAGE_FS="ext2"    # filesystem to use, must be supported by "mkfs." command and the router
GADGET_ID="usbnet"    # gadget ID used in "/sys/kernel/config/usb_gadget/ID"
GADGET_PRODUCT="$(tr -d '\0' < /sys/firmware/devicetree/base/model | sed "s/^\(.*\) Rev.*$/\1/") USB Gadget"    # product name, "Raspberry Pi Zero W USB Gadget"
GADGET_MANUFACTURER="Raspberry Pi Foundation"    # product manufacturer
GADGET_SERIAL="$(grep Serial /proc/cpuinfo | sed 's/Serial\s*: 0000\(\w*\)/\1/')"    # by default uses CPU serial
GADGET_VENDOR_ID="0x1d6b"    # 0x1d6b = Linux Foundation
GADGET_PRODUCT_ID="0x0104"    # 0x0104 = Multifunction Composite Gadget
GADGET_USB_VERSION="0x0200"    # 0x0200 = USB 2.0, should be left unchanged
GADGET_DEVICE_VERSION="0x0100"    # should be incremented every time you change your setup
GADGET_DEVICE_CLASS="0xef"    # 0xef = Multi-interface device, see https://www.usb.org/defined-class-codes
GADGET_DEVICE_SUBCLASS="0x02"    # 0x02 = Interface Association Descriptor sub class
GADGET_DEVICE_PROTOCOL="0x01"    # 0x01 = Interface Association Descriptor protocol
GADGET_MAX_PACKET_SIZE="0x40"    # declare max packet size, decimal or hex
GADGET_ATTRIBUTES="0x80"    # 0xc0 = self powered, 0x80 = bus powered
GADGET_MAX_POWER="250"    # declare max power usage, decimal or hex
GADGET_MAC_BASE="$(echo "$GADGET_SERIAL" | sed 's/\(\w\w\)/:\1/g' | cut -b 2-)"    # base MAC address generated from CPU serial
GADGET_MAC_HOST_PREFIX="02"    # prefix to use in generated MAC address
GADGET_MAC_DEVICE_PREFIX="12"    # prefix to use in generated MAC address
GADGET_MAC_HOST=""    # if empty MAC address is generated from CPU serial
GADGET_MAC_DEVICE=""    # if empty MAC address is generated from CPU serial
GADGET_STORAGE_FILE="/tmp/$GADGET_ID.img"    # path to the temporary image file that will be created and mounted
GADGET_STORAGE_STALL=""    # change value of stall option, empty means default

readonly CONFIG_FILE="/etc/asuswrt-usb-network.conf"
if [ -f "$CONFIG_FILE" ]; then
	. "$CONFIG_FILE"
fi

readonly CONFIGFS_DEVICE_PATH="/sys/kernel/config/usb_gadget/$GADGET_ID"

##################################################

gadget_up() {
	local FUNCTION="${1:lower}"
	local CONFIG="c.1"
	local INSTANCE="0"

	if [ -d "$CONFIGFS_DEVICE_PATH" ]; then
		[ -n "$(cat "$CONFIGFS_DEVICE_PATH/UDC")" ] && { echo "Gadget \"$GADGET_ID\" is already up"; exit 16; }

		echo "Cleaning up old gadget \"$GADGET_ID\"...";
		gadget_down silent
	fi

	modprobe libcomposite

	echo "Setting up gadget \"$GADGET_ID\" with function \"$FUNCTION\"..."

	mkdir "$CONFIGFS_DEVICE_PATH"

	echo "$GADGET_VENDOR_ID" > "$CONFIGFS_DEVICE_PATH/idVendor"
	echo "$GADGET_PRODUCT_ID" > "$CONFIGFS_DEVICE_PATH/idProduct"
	echo "$GADGET_USB_VERSION" > "$CONFIGFS_DEVICE_PATH/bcdUSB"
	echo "$GADGET_DEVICE_VERSION" > "$CONFIGFS_DEVICE_PATH/bcdDevice"
	echo "$GADGET_DEVICE_CLASS" > "$CONFIGFS_DEVICE_PATH/bDeviceClass"
	echo "$GADGET_DEVICE_SUBCLASS" > "$CONFIGFS_DEVICE_PATH/bDeviceSubClass"
	echo "$GADGET_DEVICE_PROTOCOL" > "$CONFIGFS_DEVICE_PATH/bDeviceProtocol"
	echo "$GADGET_MAX_PACKET_SIZE" > "$CONFIGFS_DEVICE_PATH/bMaxPacketSize0"

	mkdir "$CONFIGFS_DEVICE_PATH/strings/0x409"
	echo "$GADGET_PRODUCT" > "$CONFIGFS_DEVICE_PATH/strings/0x409/product"
	echo "$GADGET_MANUFACTURER" > "$CONFIGFS_DEVICE_PATH/strings/0x409/manufacturer"
	echo "$GADGET_SERIAL" > "$CONFIGFS_DEVICE_PATH/strings/0x409/serialnumber"

	mkdir "$CONFIGFS_DEVICE_PATH/configs/$CONFIG"
	echo "$GADGET_ATTRIBUTES" > "$CONFIGFS_DEVICE_PATH/configs/$CONFIG/bmAttributes"
	echo "$GADGET_MAX_POWER" > "$CONFIGFS_DEVICE_PATH/configs/$CONFIG/MaxPower"
	mkdir "$CONFIGFS_DEVICE_PATH/configs/$CONFIG/strings/0x409"

	case "$FUNCTION" in
		"ecm"|"rndis"|"eem"|"ncm")
			mkdir "$CONFIGFS_DEVICE_PATH/functions/$FUNCTION.$INSTANCE"

			local GADGET_MAC_BASE_CUT="$(echo "$GADGET_MAC_BASE" | cut -b 3-)"
			[ -z "$GADGET_MAC_HOST" ] && GADGET_MAC_HOST="${GADGET_MAC_HOST_PREFIX}${GADGET_MAC_BASE_CUT}"
			[ -z "$GADGET_MAC_DEVICE" ] && GADGET_MAC_DEVICE="${GADGET_MAC_DEVICE_PREFIX}${GADGET_MAC_BASE_CUT}"

			echo "$GADGET_MAC_HOST"  > "$CONFIGFS_DEVICE_PATH/functions/$FUNCTION.$INSTANCE/dev_addr"
			echo "$GADGET_MAC_DEVICE" > "$CONFIGFS_DEVICE_PATH/functions/$FUNCTION.$INSTANCE/host_addr"

			echo "${FUNCTION:upper}" > "$CONFIGFS_DEVICE_PATH/configs/$CONFIG/strings/0x409/configuration"

			ln -s "$CONFIGFS_DEVICE_PATH/functions/$FUNCTION.$INSTANCE" "$CONFIGFS_DEVICE_PATH/configs/$CONFIG"
		;;
		"mass_storage")
			mkdir "$CONFIGFS_DEVICE_PATH/functions/mass_storage.$INSTANCE"
		
			[ -n "$GADGET_STORAGE_STALL" ] && echo "$GADGET_STORAGE_STALL" > "$CONFIGFS_DEVICE_PATH/functions/mass_storage.$INSTANCE/stall"

			[ ! -d "$CONFIGFS_DEVICE_PATH/functions/mass_storage.$INSTANCE/lun.0" ] && mkdir "$CONFIGFS_DEVICE_PATH/functions/mass_storage.$INSTANCE/lun.0"
			
			if [ -n "$GADGET_STORAGE_FILE" ] && [ -f "$GADGET_STORAGE_FILE" ]; then
				[ ! -f "$GADGET_STORAGE_FILE" ] && { echo "Image file does not exist: $GADGET_STORAGE_FILE"; exit 2; }

				echo "$GADGET_STORAGE_FILE" > "$CONFIGFS_DEVICE_PATH/functions/mass_storage.$INSTANCE/lun.0/file"
			fi

			echo "Mass Storage" > "$CONFIGFS_DEVICE_PATH/configs/$CONFIG/strings/0x409/configuration"

			ln -s "$CONFIGFS_DEVICE_PATH/functions/mass_storage.$INSTANCE" "$CONFIGFS_DEVICE_PATH/configs/$CONFIG"
		;;
		*)
			echo "Invalid function specified: $FUNCTION"
			exit 22
		;;
	esac

	udevadm settle -t 5 || :
	ls /sys/class/udc > "$CONFIGFS_DEVICE_PATH/UDC"

	if [ -f "$CONFIGFS_DEVICE_PATH/functions/$FUNCTION.$INSTANCE/ifname" ]; then
		local INTERFACE="$(cat "$CONFIGFS_DEVICE_PATH/functions/$FUNCTION.$INSTANCE/ifname")"

		ifconfig "$INTERFACE" up
	fi
}

gadget_down() {
	local ARG="$1"

	[ ! -d "$CONFIGFS_DEVICE_PATH" ] && { echo "Gadget \"$GADGET_ID\" is already down"; exit 19; }

	[ "$ARG" != "silent" ] && echo "Taking down gadget \"$GADGET_ID\"...";

	if [ -d "$CONFIGFS_DEVICE_PATH" ]; then
		[ -n "$(cat "$CONFIGFS_DEVICE_PATH/UDC")" ] && echo "" > "$CONFIGFS_DEVICE_PATH/UDC"

		local INSTANCE_NET=$(find $CONFIGFS_DEVICE_PATH/functions/ -maxdepth 2 -name "ifname" | grep -o '/*[^.]*/$' || echo "")

		if [ -n "$INSTANCE_NET" ] && [ -f "$CONFIGFS_DEVICE_PATH/functions/$INSTANCE_NET/ifname" ]; then
			local INTERFACE="$(cat "$CONFIGFS_DEVICE_PATH/functions/$INSTANCE_NET/ifname")"

			[ -d "/sys/class/net/$INTERFACE" ] && ifconfig "$INTERFACE" down
		fi
		
		find $CONFIGFS_DEVICE_PATH/configs/*/* -maxdepth 0 -type l -exec rm {} \; 2> /dev/null || true
		find $CONFIGFS_DEVICE_PATH/configs/*/strings/* -maxdepth 0 -type d -exec rmdir {} \; 2> /dev/null || true
		find $CONFIGFS_DEVICE_PATH/os_desc/* -maxdepth 0 -type l -exec rm {} \; 2> /dev/null || true
		find $CONFIGFS_DEVICE_PATH/functions/* -maxdepth 0 -type d -exec rmdir {} \; 2> /dev/null || true
		find $CONFIGFS_DEVICE_PATH/strings/* -maxdepth 0 -type d -exec rmdir {} \; 2> /dev/null || true
		find $CONFIGFS_DEVICE_PATH/configs/* -maxdepth 0 -type d -exec rmdir {} \; 2> /dev/null || true
		
		rmdir "$CONFIGFS_DEVICE_PATH"
	fi
}

is_started() {
	if [ -d "$CONFIGFS_DEVICE_PATH" ]; then
		local NET_INSTANCE=$(find "/sys/kernel/config/usb_gadget/$GADGET_ID/functions" -maxdepth 2 -name "ifname" || echo "")

		[ -n "$NET_INSTANCE" ] && return 0
	fi

	return 1
}

create_image() {
	local FILE="$1"
	local FILESYSTEM="$2"
	local SIZE="$3"
	local COUNT="$4"

	command -v "mkfs.$FILESYSTEM" >/dev/null 2>&1 || { echo "Function \"mkfs.$FILESYSTEM\" not found"; exit 22; }

	echo "Creating image file \"$FILE\" ($FILESYSTEM, $COUNT*$SIZE)..."
	
	{ DD_OUTPUT=$(dd if=/dev/zero of="$FILE" bs="$SIZE" count="$COUNT" 2>&1); } || { echo "$DD_OUTPUT"; exit 1; }
	{ MKFS_OUTPUT=$("mkfs.$FILESYSTEM" "$FILE" 2>&1); } || { echo "$MKFS_OUTPUT"; exit 1; }
}

interrupt() {
	echo -e "\rInterrupt by user, cleaning up..."

	is_started || gadget_down silent
	rm -f "$GADGET_STORAGE_FILE"
}

##################################################

case "$1" in
	"start")
		is_started && { echo "Startup already complete"; exit; }

		trap interrupt SIGINT SIGTERM SIGQUIT
		set -e

		[ -d "$CONFIGFS_DEVICE_PATH" ] && gadget_down

		if [ "$SKIP_MASS_STORAGE" = false ]; then
			create_image "$GADGET_STORAGE_FILE" "$TEMP_IMAGE_FS" "$TEMP_IMAGE_SIZE" "$TEMP_IMAGE_COUNT"
			gadget_up "mass_storage"

			MS_INSTANCE=$(find "/sys/kernel/config/usb_gadget/$GADGET_ID/functions" -maxdepth 1 -name "mass_storage.*" | grep -o '[^.]*$' || echo "")
			LUN_INSTANCE=$(find "/sys/kernel/config/usb_gadget/$GADGET_ID/functions/mass_storage.$MS_INSTANCE" -maxdepth 1 -name "lun.*" | grep -o '[^.]*$' || echo "")

			{ [ -z "$MS_INSTANCE" ] || [ -z "$LUN_INSTANCE" ]; } && { echo "Could not find function or LUN instance"; exit 2; }

			echo "Waiting for the router to write to the image (timeout: ${WAIT_TIMEOUT}s)...."

			_TIMER=0
			_TIMEOUT=$WAIT_TIMEOUT
			while ! debugfs -R "ls -l ." "$GADGET_STORAGE_FILE" 2>/dev/null | grep -q txt && [ "$_TIMER" -lt "$_TIMEOUT" ]; do
				_TIMER=$((_TIMER+WAIT_SLEEP))
				sleep $WAIT_SLEEP
			done

			[ "$_TIMER" -ge "$_TIMEOUT" ] && echo "Timeout reached, continuing anyway..."

			gadget_down
			rm -f "$GADGET_STORAGE_FILE"
		fi

		gadget_up "$NETWORK_FUNCTION"

		NET_INSTANCE=$(find "/sys/kernel/config/usb_gadget/$GADGET_ID/functions" -maxdepth 1 -name "$NETWORK_FUNCTION.*" | grep -o '[^.]*$' || echo "")
		NET_INTERFACE=$(cat "/sys/kernel/config/usb_gadget/$GADGET_ID/functions/$NETWORK_FUNCTION.$NET_INSTANCE/ifname")

		{ [ -z "$NET_INSTANCE" ] || [ -z "$NET_INTERFACE" ]; } && { echo "Could not find function instance or read assigned network interface"; exit 2; }

		trap - SIGINT SIGTERM SIGQUIT

		if [ "$VERIFY_CONNECTION" = true ]; then
			echo "Checking if router is reachable (timeout: ${VERIFY_TIMEOUT}s)..."
			
			_TIMER=0
			_TIMEOUT=$VERIFY_TIMEOUT
			while [ "$_TIMER" -lt "$_TIMEOUT" ]; do
				GATEWAY="$(ip route show | grep "$NET_INTERFACE" | grep default | awk '{print $3}')"

				[ -n "$GATEWAY" ] && ping -c1 -W1 "$GATEWAY" >/dev/null 2>&1 && break

				_TIMER=$((_TIMER+VERIFY_SLEEP))
				sleep $VERIFY_SLEEP
			done

			[ "$_TIMER" -ge "$_TIMEOUT" ] && { echo "Completed but couldn't determine network status (timeout reached)"; exit 124; }
		fi

		echo "Completed successfully"
	;;
	"stop")
		gadget_down
	;;
	*)
		echo "Usage: $0 start|stop"
		exit 1
	;;
esac
