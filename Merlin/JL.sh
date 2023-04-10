#!/bin/sh
# Made by Jack'lul <jacklul.github.io>

#shellcheck disable=SC1091
. /usr/sbin/helper.sh

ADDON_NAME=JL
ADDON_DIR=/jffs/addons/$ADDON_NAME
SCRIPTS_DIR=/jffs/scripts
DOWNLOAD_BASE=https://raw.githubusercontent.com/jacklul/asuswrt-scripts/master
DOWNLOAD_BASE_SCRIPTS="$DOWNLOAD_BASE/scripts"
DOWNLOAD_BASE_ADDON="$DOWNLOAD_BASE/Merlin"

jl_register_custom_page() {
	am_get_webui_page "$ADDON_DIR/$ADDON_NAME.asp"

	#shellcheck disable=SC2154
	if [ "$am_webui_page" != "none" ]; then
		cp "$ADDON_DIR/$ADDON_NAME.asp" "/www/user/$am_webui_page"

		if [ ! -f /tmp/menuTree.js ]; then
			cp /www/require/modules/menuTree.js /tmp/
			mount -o bind /tmp/menuTree.js /www/require/modules/menuTree.js
		fi

		sed -i "/url: \"Tools_OtherSettings.asp\", tabName:/a {url: \"$am_webui_page\", tabName: \"$ADDON_NAME\"}," /tmp/menuTree.js

		umount /www/require/modules/menuTree.js && mount -o bind /tmp/menuTree.js /www/require/modules/menuTree.js
	else
		logger -t "$ADDON_NAME" "Unable to install custom page"
	fi
}

jl_services() {
	if [ "$(am_settings_get jl_pkiller)" = "true" ] && [ "$1" != "uninstall" ]; then
		if [ ! -f "$SCRIPTS_DIR/process-killer.sh" ]; then
			curl "$DOWNLOAD_BASE_SCRIPTS/process-killer.sh" -o "$SCRIPTS_DIR/process-killer.sh" && \
			chmod +x "$SCRIPTS_DIR/process-killer.sh"
		fi

		"$SCRIPTS_DIR/process-killer.sh" start &
	elif [ -f "$SCRIPTS_DIR/process-killer.sh" ]; then
		"$SCRIPTS_DIR/process-killer.sh" stop
	fi

	if [ "$(am_settings_get jl_usbnetwork)" = "true" ] && [ "$1" != "uninstall" ]; then
		if [ ! -f "$SCRIPTS_DIR/usb-network.sh" ]; then
			curl "$DOWNLOAD_BASE_SCRIPTS/usb-network.sh" -o "$SCRIPTS_DIR/usb-network.sh" && \
			chmod +x "$SCRIPTS_DIR/usb-network.sh"
		fi

		"$SCRIPTS_DIR/usb-network.sh" start &
	elif [ -f "$SCRIPTS_DIR/usb-network.sh" ]; then
		"$SCRIPTS_DIR/usb-network.sh" stop
	fi

	if [ "$(am_settings_get jl_swap)" = "true" ] && [ "$1" != "uninstall" ]; then
		if [ ! -f "$SCRIPTS_DIR/swap.sh" ]; then
			curl "$DOWNLOAD_BASE_SCRIPTS/swap.sh" -o "$SCRIPTS_DIR/swap.sh" && \
			chmod +x "$SCRIPTS_DIR/swap.sh"
		fi

		if [ -f /jffs/scripts/post-mount ]; then
			if ! grep -q "$SCRIPTS_DIR/swap.sh" /jffs/scripts/post-mount; then
				echo "$SCRIPTS_DIR/swap.sh start \"\$1\" #$ADDON_NAME#" >> /jffs/scripts/post-mount
			fi
		else
			echo "#!/bin/sh" > /jffs/scripts/post-mount
			echo "" >> /jffs/scripts/post-mount
			echo "$SCRIPTS_DIR/swap.sh start \"\$1\" #$ADDON_NAME#" >> /jffs/scripts/post-mount
			chmod 0755 /jffs/scripts/post-mount
		fi

		"$SCRIPTS_DIR/swap.sh" start &
	else
		if [ -f /jffs/scripts/post-mount ]; then
			if grep -q "$SCRIPTS_DIR/swap.sh" /jffs/scripts/post-mount; then
				sed -i -e "\_$SCRIPTS_DIR/swap.sh_d" /jffs/scripts/post-mount
			fi
		fi
	fi

	if [ "$(am_settings_get jl_disablewps)" = "true" ] && [ "$1" != "uninstall" ]; then
		if [ ! -f "$SCRIPTS_DIR/disable-wps.sh" ]; then
			curl "$DOWNLOAD_BASE_SCRIPTS/disable-wps.sh" -o "$SCRIPTS_DIR/disable-wps.sh" && \
			chmod +x "$SCRIPTS_DIR/disable-wps.sh"
		fi

		"$SCRIPTS_DIR/disable-wps.sh" start &
	elif [ -f "$SCRIPTS_DIR/disable-wps.sh" ]; then
		"$SCRIPTS_DIR/disable-wps.sh" stop
	fi

	if [ "$(am_settings_get jl_ledcontrol)" = "true" ] && [ "$1" != "uninstall" ]; then
		if [ ! -f "$SCRIPTS_DIR/led-control.sh" ]; then
			curl "$DOWNLOAD_BASE_SCRIPTS/led-control.sh" -o "$SCRIPTS_DIR/led-control.sh" && \
			chmod +x "$SCRIPTS_DIR/led-control.sh"
		fi

		"$SCRIPTS_DIR/led-control.sh" start &
	elif [ -f "$SCRIPTS_DIR/led-control.sh" ]; then
		"$SCRIPTS_DIR/led-control.sh" stop
	fi

	if [ "$(am_settings_get jl_creboot)" = "true" ] && [ "$1" != "uninstall" ]; then
		if [ ! -f "$SCRIPTS_DIR/conditional-reboot.sh" ]; then
			curl "$DOWNLOAD_BASE_SCRIPTS/conditional-reboot.sh" -o "$SCRIPTS_DIR/conditional-reboot.sh" && \
			chmod +x "$SCRIPTS_DIR/conditional-reboot.sh"
		fi

		"$SCRIPTS_DIR/conditional-reboot.sh" start &
	elif [ -f "$SCRIPTS_DIR/conditional-reboot.sh" ]; then
		"$SCRIPTS_DIR/conditional-reboot.sh" stop
	fi

	if [ "$(am_settings_get jl_rbackup)" = "true" ] && [ "$1" != "uninstall" ]; then
		if [ ! -f "$SCRIPTS_DIR/rclone-backup.sh" ]; then
			curl "$DOWNLOAD_BASE_SCRIPTS/rclone-backup.sh" -o "$SCRIPTS_DIR/rclone-backup.sh" && \
			chmod +x "$SCRIPTS_DIR/rclone-backup.sh"
		fi

		"$SCRIPTS_DIR/rclone-backup.sh" start &
	elif [ -f "$SCRIPTS_DIR/rclone-backup.sh" ]; then
		"$SCRIPTS_DIR/rclone-backup.sh" stop
	fi

	if [ "$(am_settings_get jl_twarning)" = "true" ] && [ "$1" != "uninstall" ]; then
		if [ ! -f "$SCRIPTS_DIR/temperature-warning.sh" ]; then
			curl "$DOWNLOAD_BASE_SCRIPTS/temperature-warning.sh" -o "$SCRIPTS_DIR/temperature-warning.sh" && \
			chmod +x "$SCRIPTS_DIR/temperature-warning.sh"
		fi

		"$SCRIPTS_DIR/temperature-warning.sh" start &
	elif [ -f "$SCRIPTS_DIR/temperature-warning.sh" ]; then
		"$SCRIPTS_DIR/temperature-warning.sh" stop
	fi

	if [ "$(am_settings_get jl_diskcheck)" = "true" ] && [ "$1" != "uninstall" ]; then
		if [ ! -f "$SCRIPTS_DIR/disk-check.sh" ]; then
			curl "$DOWNLOAD_BASE_ADDON/scripts/disk-check.sh" -o "$SCRIPTS_DIR/disk-check.sh" && \
			chmod +x "$SCRIPTS_DIR/disk-check.sh"
		fi

		if [ -f /jffs/scripts/pre-mount ]; then
			if ! grep -q "$SCRIPTS_DIR/disk-check.sh" /jffs/scripts/pre-mount; then
				echo "$SCRIPTS_DIR/disk-check.sh \"\$1\" \"\$2\" #$ADDON_NAME#" >> /jffs/scripts/pre-mount
			fi
		else
			echo "#!/bin/sh" > /jffs/scripts/pre-mount
			echo "" >> /jffs/scripts/pre-mount
			echo "$SCRIPTS_DIR/disk-check.sh \"\$1\" \"\$2\" #$ADDON_NAME#" >> /jffs/scripts/pre-mount
			chmod 0755 /jffs/scripts/pre-mount
		fi
	else
		if [ -f /jffs/scripts/pre-mount ]; then
			if grep -q "$SCRIPTS_DIR/disk-check.sh" /jffs/scripts/pre-mount; then
				sed -i -e "\_$SCRIPTS_DIR/disk-check.sh_d" /jffs/scripts/pre-mount
			fi
		fi
	fi

	if [ "$(am_settings_get jl_unotify)" = "true" ] && [ "$1" != "uninstall" ]; then
		if [ ! -f "$SCRIPTS_DIR/update-notify.sh" ]; then
			curl "$DOWNLOAD_BASE_SCRIPTS/update-notify.sh" -o "$SCRIPTS_DIR/update-notify.sh" && \
			chmod +x "$SCRIPTS_DIR/update-notify.sh"
		fi

		if [ -f /jffs/scripts/update-notification ]; then
			if ! grep -q "$SCRIPTS_DIR/update-notify.sh" /jffs/scripts/update-notification; then
				echo "$SCRIPTS_DIR/update-notify.sh run #$ADDON_NAME#" >> /jffs/scripts/update-notification
			fi
		else
			echo "#!/bin/sh" > /jffs/scripts/update-notification
			echo "" >> /jffs/scripts/update-notification
			echo "$SCRIPTS_DIR/update-notify.sh run #$ADDON_NAME#" >> /jffs/scripts/update-notification
			chmod 0755 /jffs/scripts/update-notification
		fi
	else
		if [ -f /jffs/scripts/update-notification ]; then
			if grep -q "$SCRIPTS_DIR/update-notify.sh" /jffs/scripts/update-notification; then
				sed -i -e "\_$SCRIPTS_DIR/update-notify.sh run_d" /jffs/scripts/update-notification
			fi
		fi
	fi
}

jl_md5_compare() {
	if [ -n "$1" ] && [ -n "$2" ]; then
		if [ "$(md5sum "$1" | awk '{print $1}')" = "$(md5sum "$2" | awk '{print $1}')" ]; then
			return 0
		fi
	fi

	return 1
}

jl_download_and_check() {
	if [ -n "$1" ] && [ -n "$2" ]; then
		if curl "$1" -o "/tmp/download_tmp"; then
			if ! jl_md5_compare "/tmp/download_tmp" "$2"; then
				mv "/tmp/download_tmp" "$2"
			fi
		fi

		rm -f "/tmp/download_tmp"
	fi
}

case "$1" in
    "start")
		jl_register_custom_page
		jl_services start
    ;;
    "service")
		if [ "$3" = "$ADDON_NAME" ]; then
			case $2 in
				"restart")
					jl_services restart
				;;
				*)
					logger -t "$ADDON_NAME" "Received unsupported service event: $2"
				;;
			esac
		fi
    ;;
    "update")
		set -e

		# Addon
		jl_download_and_check "$DOWNLOAD_BASE_ADDON/JL.sh" "$ADDON_DIR/$ADDON_NAME.sh"
		jl_download_and_check "$DOWNLOAD_BASE_ADDON/JL.asp" "$ADDON_DIR/$ADDON_NAME.asp"
		[ -f "$SCRIPTS_DIR/disk-check.sh" ] && jl_download_and_check "$DOWNLOAD_BASE_ADDON/scripts/disk-check.sh" "$SCRIPTS_DIR/disk-check.sh"

		# Scripts
		[ -f "$SCRIPTS_DIR/conditional-reboot.sh" ] && jl_download_and_check "$DOWNLOAD_BASE_SCRIPTS/conditional-reboot.sh" "$SCRIPTS_DIR/conditional-reboot.sh"
		[ -f "$SCRIPTS_DIR/disable-wps.sh" ] && jl_download_and_check "$DOWNLOAD_BASE_SCRIPTS/disable-wps.sh" "$SCRIPTS_DIR/disable-wps.sh"
		[ -f "$SCRIPTS_DIR/led-control.sh" ] && jl_download_and_check "$DOWNLOAD_BASE_SCRIPTS/led-control.sh" "$SCRIPTS_DIR/led-control.sh"
		[ -f "$SCRIPTS_DIR/process-killer.sh" ] && jl_download_and_check "$DOWNLOAD_BASE_SCRIPTS/process-killer.sh" "$SCRIPTS_DIR/process-killer.sh"
		[ -f "$SCRIPTS_DIR/rclone-backup.sh" ] && jl_download_and_check "$DOWNLOAD_BASE_SCRIPTS/rclone-backup.sh" "$SCRIPTS_DIR/rclone-backup.sh"
		[ -f "$SCRIPTS_DIR/rclone-backup.list" ] && jl_download_and_check "$DOWNLOAD_BASE_SCRIPTS/rclone-backup.list" "$SCRIPTS_DIR/rclone-backup.list"
		[ -f "$SCRIPTS_DIR/swap.sh" ] && jl_download_and_check "$DOWNLOAD_BASE_SCRIPTS/swap.sh" "$SCRIPTS_DIR/swap.sh"
		[ -f "$SCRIPTS_DIR/temperature-warning.sh" ] && jl_download_and_check "$DOWNLOAD_BASE_SCRIPTS/temperature-warning.sh" "$SCRIPTS_DIR/temperature-warning.sh"
		[ -f "$SCRIPTS_DIR/update-notify.sh" ] && jl_download_and_check "$DOWNLOAD_BASE_SCRIPTS/update-notify.sh" "$SCRIPTS_DIR/update-notify.sh"
		[ -f "$SCRIPTS_DIR/usb-network.sh" ] && jl_download_and_check "$DOWNLOAD_BASE_SCRIPTS/usb-network.sh" "$SCRIPTS_DIR/usb-network.sh"
    ;;
    "install")
		nvram get rc_support | grep -q am_addons || { echo "This firmware does not support addons!"; exit 1; }

		echo "Installing..."

		set -e

		if [ ! -f "$ADDON_DIR/$ADDON_NAME.sh" ]; then
			[ ! -d "$ADDON_DIR" ] && mkdir -p "$ADDON_DIR"

			if [ -f "$0" ]; then
				mv "$0" "$ADDON_DIR/$ADDON_NAME.sh"
			else
				curl "$DOWNLOAD_BASE/Merlin/JL.sh" -o "$ADDON_DIR/$ADDON_NAME.sh"
			fi

			chmod +x "$ADDON_DIR/$ADDON_NAME.sh"

			if [ ! -f "$ADDON_DIR/$ADDON_NAME.asp" ]; then
				curl "$DOWNLOAD_BASE/Merlin/JL.asp" -o "$ADDON_DIR/$ADDON_NAME.asp"
			fi
		fi

		[ ! -d /jffs/scripts ] && mkdir -p /jffs/scripts
		
		if [ -f /jffs/scripts/services-start ]; then
			if ! grep -q "$ADDON_DIR/$ADDON_NAME.sh" /jffs/scripts/services-start; then
				echo "$ADDON_DIR/$ADDON_NAME.sh start & #$ADDON_NAME#" >> /jffs/scripts/services-start
			fi
		else
			echo "#!/bin/sh" > /jffs/scripts/services-start
			echo "" >> /jffs/scripts/services-start
			echo "$ADDON_DIR/$ADDON_NAME.sh start & #$ADDON_NAME#" >> /jffs/scripts/services-start
			chmod 0755 /jffs/scripts/services-start
		fi

		if [ -f /jffs/scripts/service-event ]; then
			if ! grep -q "$ADDON_DIR/$ADDON_NAME.sh" /jffs/scripts/service-event; then
				echo "[ \"\$2\" = \"$ADDON_NAME\" ] && $ADDON_DIR/$ADDON_NAME.sh service \$* #$ADDON_NAME#" >> /jffs/scripts/service-event
			fi
		else
			echo "#!/bin/sh" > /jffs/scripts/service-event
			echo "" >> /jffs/scripts/service-event
			echo "[ \"\$2\" = \"$ADDON_NAME\" ] && $ADDON_DIR/$ADDON_NAME.sh service \$* #$ADDON_NAME#" >> /jffs/scripts/service-event
			chmod 0755 /jffs/scripts/service-event
		fi

		jl_register_custom_page

		echo "Complete"
    ;;
    "uninstall")
		echo "Uninstalling..."

		jl_services uninstall

		if [ -f /jffs/scripts/services-start ]; then
			if grep -q "$ADDON_DIR/$ADDON_NAME.sh" /jffs/scripts/services-start; then
				sed -i -e "\_$ADDON_DIR/${ADDON_SCRIPT}_d" /jffs/scripts/services-start
			fi
		fi

		if [ -f /jffs/scripts/service-event-end ]; then
			if grep -q "$ADDON_DIR/$ADDON_NAME.sh" /jffs/scripts/service-event-end; then
				sed -i -e "\_$ADDON_DIR/${ADDON_SCRIPT}_d" /jffs/scripts/service-event-end
			fi
		fi

		echo "Reboot to complete the uninstall"
    ;;
    *)
        echo "Usage: $0 "
        exit 1
    ;;
esac
