#!/bin/sh

[ -f "/rom/jffs.json" ] || { echo "This script must run on the Asus router!"; exit 1; }

set -e

echo "Downloading required scripts..."

[ ! -f "/tmp/startup.sh" ] && curl "https://raw.githubusercontent.com/jacklul/asuswrt-scripts/master/startup.sh" -o "/tmp/startup.sh"
[ ! -f "/tmp/usb-network.sh" ] && curl "https://raw.githubusercontent.com/jacklul/asuswrt-scripts/master/scripts/usb-network.sh" -o "/tmp/usb-network.sh"

MODIFICATION="        # asuswrt-usb-raspberry-pi #
        MOUNTED_PATHS=\"\$(df | grep /dev/sd | awk '{print \$NF}')\"

        if [ -n \"\$MOUNTED_PATHS\" ]; then
            for MOUNTED_PATH in \$MOUNTED_PATHS; do
                touch \"\$MOUNTED_PATH/txt\"
            done
        else
            logger -s -t \"\$SCRIPT_NAME\" \"Could not find storage mount point\"
        fi

        sync
        ejusb -1 0
        # asuswrt-usb-raspberry-pi #
"

echo "Modifying startup script..."

if ! grep -q "# asuswrt-usb-raspberry-pi #" "/tmp/startup.sh"; then
    LINE="$(grep -Fn "f \"\$CHECK_FILE\" ]; then" "/tmp/startup.sh")"

    [ -z "$LINE" ] && { echo "Failed to modify /tmp/startup.sh - unable to find correct line"; exit 1; }
    
    LINE="$(echo "$LINE" | cut -d":" -f1)"
    LINE=$((LINE-1))
    MD5="$(md5sum "/tmp/startup.sh")"

    #shellcheck disable=SC2005
    echo "$({ head -n $((LINE)) /tmp/startup.sh; echo "$MODIFICATION"; tail -n +$((LINE+1)) /tmp/startup.sh; })" > /tmp/startup.sh

    [ "$MD5" = "$(md5sum "/tmp/startup.sh")" ] && { echo "Failed to modify /tmp/startup.sh - modification failed"; exit 1; }
else
    echo "Seems like /tmp/startup.sh is already modified"
fi

echo "Setting permissions..."

chmod +x "/tmp/startup.sh" "/tmp/usb-network.sh"

echo "Moving files..."

mv -v "/tmp/startup.sh" "/jffs/startup.sh"
mkdir -vp "/jffs/scripts"
mv -v "/tmp/usb-network.sh" "/jffs/scripts/usb-network.sh"

echo "Running "startup.sh install"..."

/jffs/startup.sh install

echo "Finished"
