#!/bin/sh
# Made by Jack'lul <jacklul.github.io>
#
# This script starts all other scripts
# Only scripts containing "start") or start) will be interacted with
#

#jacklul-asuswrt-scripts-update=scripts-startup.sh
#shellcheck disable=SC2155

readonly script_path="$(readlink -f "$0")"
readonly script_name="$(basename "$script_path" .sh)"
readonly script_dir="$(dirname "$script_path")"
readonly script_config="$script_dir/$script_name.conf"

SCRIPTS_DIR="$script_dir"
CHECK_FILE="/tmp/scripts_started"
PRIORITIES="service-event.sh hotplug-event.sh custom-configs.sh cron-queue.sh"

umask 022 # set default umask

if [ -f "$script_config" ]; then
    #shellcheck disable=SC1090
    . "$script_config"
fi

is_merlin_firmware() { #ISMERLINFIRMWARE_START#
    if [ -f "/usr/sbin/helper.sh" ]; then
        return 0
    fi
    return 1
} #ISMERLINFIRMWARE_END#

call_action() {
    _entry="$1"
    _action="$2"

    case "$_action" in
        "start")
            logger -st "$script_name" "Starting '$_entry'..."
        ;;
        "stop")
            logger -st "$script_name" "Stopping '$_entry'..."
        ;;
        "restart")
            logger -st "$script_name" "Restarting '$_entry'..."
        ;;
        *)
            echo "Unknown action: $_action"
            return
    esac

    /bin/sh "$_entry" "$_action"
}

scripts() {
    _action="$1"

    [ ! -d "$SCRIPTS_DIR" ] && return

    if [ -n "$PRIORITIES" ] && [ "$_action" = "start" ]; then
        for _entry in $PRIORITIES; do
            if [ -x "$SCRIPTS_DIR/$_entry" ]; then
                call_action "$SCRIPTS_DIR/$_entry" start
            fi
        done
    fi

    for _entry in "$SCRIPTS_DIR"/*.sh; do
        _entry="$(readlink -f "$_entry")"

        # Do not start priority scripts again
        if [ "$_action" = "start" ] && echo "$PRIORITIES" | grep -Fq "$(basename "$_entry")"; then
            continue
        fi

        [ "$_entry" = "$script_path" ] && continue # do not interact with itself, just in case
        { ! grep -Fq "\"start\")" "$_entry" && ! grep -Fq "start)" "$_entry" ; } && continue # require 'start' case

        if [ -x "$_entry" ]; then
            call_action "$_entry" "$_action"
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
        #shellcheck disable=SC2174
        mkdir -pvm 755 "$SCRIPTS_DIR"

        if is_merlin_firmware; then
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

                    if ! grep -Fq "$script_path" /jffs/scripts/services-start; then
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

                echo "Waiting for 15 seconds to verify that the value is still set..."
                sleep 15

                if [ -z "$(nvram get script_usbmount)" ]; then
                    cat <<EOT
Value has been cleaned by the router - you will have to use a workaround:
https://github.com/jacklul/asuswrt-scripts/tree/legacy/asusware-usbmount
EOT
                else
                    nvram commit
                fi
            else
                echo "NVRAM variable 'script_usbmount' is already set to '$NVRAM_SCRIPT'"
            fi
        fi
    ;;
    *)
        echo "Usage: $0 start|stop|restart|install"
        exit 1
    ;;
esac
