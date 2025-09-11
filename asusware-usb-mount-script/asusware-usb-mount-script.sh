#!/bin/sh
# Installer for https://github.com/jacklul/asuswrt-scripts/tree/master/asusware-usb-mount-script

[ ! -d /jffs ] && { echo "Could not find /jffs"; exit 1; }
type unzip > /dev/null 2>&1 || { echo "Could not find the 'unzip' command"; exit 1; }

branch=master
[ -n "$1" ] && branch="$1"
zip_url="https://raw.githubusercontent.com/jacklul/asuswrt-scripts/$branch/asusware-usb-mount-script/asusware-usb-mount-script.zip"

set -e
umask 022

apps_install_folder="$(nvram get apps_install_folder 2> /dev/null)"
[ -z "$apps_install_folder" ] && { echo "NVRAM variable 'apps_install_folder' is empty"; exit 1; }

for dir in /tmp/mnt/*; do
    if [ -d "$dir" ] && mount | grep -F "/dev" | grep -Fq "$dir"; then
        if [ -d "$dir/$apps_install_folder" ]; then
            echo "Already installed in '$dir/$apps_install_folder'"
            exit 0
        fi

        storage_dir="$dir"
        break
    fi
done

[ -z "$storage_dir" ] && { echo "No storage is mounted"; exit 1; }

echo "Detected mounted storage: $storage_dir"
#shellcheck disable=SC3045,SC2162
read -p "Do you wish continue ? [y/N] " response

case "$response" in
    [Yy]*|[Yy][Ee][Ss]*) 
        case "$apps_install_folder" in # app_check_folder.sh
            "asusware.arm") apps_arch=arm ;;
            "asusware.big") apps_arch=mipsbig ;;
            "asusware.mipsbig") apps_arch=mipsbig ;;
            "asusware") apps_arch=mipsel ;;
            *) echo "Unsupported 'apps_install_folder' value: $apps_install_folder"; exit 1 ;;
        esac

        if [ -n "$apps_arch" ]; then
            if type curl > /dev/null 2>&1; then
                curl "$zip_url" -o /tmp/asusware-usbmount.zip
            elif type wget > /dev/null 2>&1; then
                wget "$zip_url" -O /tmp/asusware-usbmount.zip
            else
                echo "Could not find either the 'curl' or 'wget' command!"
                exit 1
            fi

            unzip /tmp/asusware-usbmount.zip -d "$storage_dir"
            rm /tmp/asusware-usbmount.zip
            find "$storage_dir/asusware.arm" -type d -exec chmod 755 {} + || true
            find "$storage_dir/asusware.arm" -type f -exec chmod 644 {} + || true
            chmod +x "$storage_dir/asusware.arm/etc/init.d/S50usb-mount-script" || true

            if [ "$apps_arch" != "arm" ]; then
                mv "$storage_dir/asusware.arm" "$storage_dir/$apps_install_folder"
                sed "s/Architecture: arm/Architecture: $apps_arch/" -i "$storage_dir/$apps_install_folder/lib/ipkg/status"
                sed "s/Architecture: arm/Architecture: $apps_arch/" -i "$storage_dir/$apps_install_folder/lib/ipkg/info/usb-mount-script.control"
                sed "s/Architecture: arm/Architecture: $apps_arch/" -i "$storage_dir/$apps_install_folder/lib/ipkg/lists/optware.asus"
            fi

            if [ ! -f /jffs/scripts/usb-mount-script ]; then
                cat <<EOT > "/jffs/scripts/usb-mount-script"
#!/bin/sh
# https://github.com/jacklul/asuswrt-scripts/tree/master/asusware-usb-mount-script

[ -t 0 ] && exit 1 # Prevent manual execution

EOT
                chmod +x "/jffs/scripts/usb-mount-script"
            fi

            echo "Successfully installed to '$storage_dir/$apps_install_folder'"
        fi
    ;;
esac
