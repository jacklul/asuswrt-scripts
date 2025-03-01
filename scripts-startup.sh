#!/bin/sh
# Made by Jack'lul <jacklul.github.io>
#
# This script starts all other scripts
# Only scripts containing "start") or start) will be interacted with
#

#shellcheck disable=SC2155

readonly script_path="$(readlink -f "$0")"
readonly script_name="$(basename "$script_path" .sh)"
readonly script_dir="$(dirname "$script_path")"
readonly script_config="$script_dir/$script_name.conf"

SCRIPTS_DIR="/jffs/scripts"
CHECK_FILE="/tmp/scripts_started"

if [ -f "$script_config" ]; then
    #shellcheck disable=SC1090
    . "$script_config"
fi

scripts() {
    readonly _ACTION="$1"

    [ ! -d "$SCRIPTS_DIR" ] && return

    for _ENTRY in "$SCRIPTS_DIR"/*.sh; do
        _ENTRY="$(readlink -f "$_ENTRY")"

        [ "$_ENTRY" = "$script_path" ] && continue # do not interact with itself, just in case
        { ! grep -q "\"start\")" "$_ENTRY" && ! grep -q "start)" "$_ENTRY" ; } && continue

        if [ -x "$_ENTRY" ]; then
            case "$_ACTION" in
                "start")
                    logger -st "$script_name" "Starting $_ENTRY..."
                ;;
                "stop")
                    logger -st "$script_name" "Stopping $_ENTRY..."
                ;;
                "restart")
                    logger -st "$script_name" "Restarting $_ENTRY..."
                ;;
                *)
                    echo "Unknown action: $_ACTION"
                    return
            esac

            /bin/sh "$_ENTRY" "$_ACTION"
        fi
    done
}

case "$1" in
    "start")
        if [ ! -f "$CHECK_FILE" ]; then
            logger -st "$script_name" "Starting custom scripts ($SCRIPTS_DIR)..."

            date "+%Y-%m-%d %H:%M:%S" > $CHECK_FILE

            scripts start
        else
            echo "Scripts were already started at $(cat "$CHECK_FILE")"
        fi
    ;;
    "stop")
        logger -st "$script_name" "Stopping custom scripts ($SCRIPTS_DIR)..."

        rm -f "$CHECK_FILE"

        scripts stop
    ;;
    "restart")
        logger -st "$script_name" "Restarting custom scripts ($SCRIPTS_DIR)..."

        scripts restart
    ;;
    "install")
        mkdir -pv "$SCRIPTS_DIR"

        if [ -f "/usr/sbin/helper.sh" ]; then # could also be [ "$(uname -o)" = "ASUSWRT-Merlin" ] ?
            cat <<EOT
You should not be using this script on Asuswrt-Merlin!
Please start individual scripts from /jffs/scripts/services-start instead!

If you continue an entry to start this script will be added to /jffs/scripts/services-start.
EOT

            #shellcheck disable=SC3045,SC2162
            read -p "Continue ? [y/N] : " -n1 REPLY
            echo

            case $REPLY in
                [Yy]*)
                    if [ ! -f /jffs/scripts/services-start ]; then
                    echo "Creating /jffs/scripts/services-start"

                    cat <<EOT > /jffs/scripts/services-start
#!/bin/sh

EOT
                    chmod 0755 /jffs/scripts/services-start
                fi

                if ! grep -q "$script_path" /jffs/scripts/services-start; then
                    echo "Adding script to /jffs/scripts/services-start"

                    echo "$script_path start & # jacklul/asuswrt-scripts" >> /jffs/scripts/services-start
                else
                    echo "Script line already exists in /jffs/scripts/services-start"
                fi
                ;;
            esac
        else
            NVRAM_SCRIPT="/bin/sh $script_path start"

            if [ "$(nvram get script_usbmount)" != "$NVRAM_SCRIPT" ]; then
                echo "Setting NVRAM variable 'script_usbmount' to '$NVRAM_SCRIPT'"

                nvram set script_usbmount="$NVRAM_SCRIPT"
                nvram commit

                echo "Waiting for 15 seconds to verify that the value is still set..."
                sleep 15

                if [ -z "$(nvram get script_usbmount)" ]; then
                    cat <<EOT
Value has been cleaned by the router - you will have to use a workaround:
https://github.com/jacklul/asuswrt-scripts/tree/master/asusware-usbmount
EOT
                fi
            else
                echo "NVRAM variable 'script_usbmount' is already set to '$NVRAM_SCRIPT'"
            fi
        fi
    ;;
    *)
        echo "Usage: $0 start|stop|install"
        exit 1
    ;;
esac
