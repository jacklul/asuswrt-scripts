#!/bin/sh
# Made by Jack'lul <jacklul.github.io>
#
# This is the main script that starts and manages all the scripts
# from https://github.com/jacklul/asuswrt-scripts repository.
#

#jas-update=jas.sh
#shellcheck disable=SC2155

readonly script_path="$(readlink -f "$0")"
readonly script_dir="$(dirname "$script_path")"
readonly script_name="$(basename "$script_path" .sh)"
readonly script_config="$script_dir/$script_name.conf"

SCRIPTS_DIR="/jffs/scripts/jas" # the directory to store the scripts, this can only be changed in jas.conf
START_FIRST="cron-queue.sh service-event.sh hotplug-event.sh" # scripts that must start first before everything else
START_LAST="custom-configs.sh process-affinity.sh swap.sh entware.sh" # scripts that must start last after everything else
BASE_URL="https://raw.githubusercontent.com/jacklul/asuswrt-scripts" # base download url, without ending slash
BRANCH="master" # which git branch to use when installing/updating scripts
SELF_UPDATE=true # self update when running 'update' action? when false this script will never be updated

#shellcheck disable=SC1090
[ -f "$script_config" ] && . "$script_config"
readonly SCRIPTS_DIR # changing this in common.conf might lead to unexpected behavior so block it
[ -z "$SCRIPTS_DIR" ] && { echo "SCRIPTS_DIR is not set!"; exit 1; }

# Load common.sh script if available and adjust some variables
readonly common_script="$SCRIPTS_DIR/common.sh"
#shellcheck source=./scripts/common.sh
if [ -f "$common_script" ]; then
    . "$common_script"
fi

download_url="$BASE_URL/$BRANCH"
[ -z "$TMP_DIR" ] && TMP_DIR=/tmp
check_file="$TMP_DIR/$script_name"
tmp_file="$TMP_DIR/$script_name.tmp"

call_action() {
    _entry="$1"
    _action="$2"

    case "$_action" in
        "start")
            if [ -f "$check_file" ]; then
                if grep -Fq "$_entry" "$check_file"; then
                    return # already started
                else
                    echo "$_entry" >> "$check_file"
                fi
            fi

            [ -z "$IS_INTERACTIVE" ] && logger -t "$script_name" "Starting '$_entry'..."
            echo "Starting '${fwe}$_entry${frt}'..."
        ;;
        "stop")
            [ -z "$IS_INTERACTIVE" ] && logger -t "$script_name" "Stopping '$_entry'..."
            echo "Stopping '${fwe}$_entry${frt}'..."
        ;;
        "restart")
            [ -z "$IS_INTERACTIVE" ] && logger -t "$script_name" "Restarting '$_entry'..."
            echo "Restarting '${fwe}$_entry${frt}'..."
        ;;
        *)
            echo "Unknown action: $_action"
            return 1
        ;;
    esac

    ( /bin/sh "$_entry" "$_action" )
}

scripts_action() {
    [ ! -d "$SCRIPTS_DIR" ] && return

    _action="$1"

    # Start scripts that must start first
    if [ -n "$START_FIRST" ] && [ "$_action" = "start" ]; then
        for _entry in $START_FIRST; do
            if [ -x "$SCRIPTS_DIR/$_entry" ]; then
                call_action "$SCRIPTS_DIR/$_entry" start
            fi
        done
    fi

    for _entry in "$SCRIPTS_DIR"/*.sh; do
        _entry="$(readlink -f "$_entry")"

        # Do not start scripts here that are in START_FIRST or START_LAST lists
        if [ "$_action" = "start" ] && echo "$START_FIRST $START_LAST" | grep -Fq "$(basename "$_entry")"; then
            continue
        fi

        [ "$_entry" = "$script_path" ] && continue # do not interact with itself, just in case
        ! grep -q "#jas-update\|#jas-custom" "$_entry" && continue # require jas-update or jas-custom tag
        { ! grep -Fq "\"start\")" "$_entry" && ! grep -Fq "start)" "$_entry" ; } && continue # require 'start' case

        if [ -x "$_entry" ]; then
            call_action "$_entry" "$_action"
        fi
    done

    # Start scripts that must start last
    if [ -n "$START_LAST" ] && [ "$_action" = "start" ]; then
        for _entry in $START_LAST; do
            if [ -x "$SCRIPTS_DIR/$_entry" ]; then
                call_action "$SCRIPTS_DIR/$_entry" start
            fi
        done
    fi
}

require_installed() {
    if [ -n "$SCRIPTS_DIR" ] && [ ! -d "$SCRIPTS_DIR" ]; then
        echo "Scripts directory '${fwe}$SCRIPTS_DIR${frt}' doesn't exist!"
        _not_installed=true
    fi

    if [ -z "$JAS_COMMON" ]; then
        echo "Shared dependency script '${fwe}common.sh${frt}' is not loaded!"
        _not_installed=true
    fi

    if [ -n "$_not_installed" ]; then
        echo "Maybe run '${fwe}$0 setup${frt}' ?"
        exit 1
    fi
}

md5sum_compare() {
    { [ ! -f "$1" ] || [ ! -f "$2" ] ; } && return 1

    if [ -n "$1" ] && [ -n "$2" ]; then
        if [ "$(md5sum "$1" 2> /dev/null | awk '{print $1}')" = "$(md5sum "$2" 2> /dev/null | awk '{print $1}')" ]; then
            return 0
        fi
    fi

    return 1
}

download_file() {
    if type fetch > /dev/null 2>&1; then
        fetch "$1" "$2"
        return $?
    fi

    # fallback when common.sh does not yet exist
    if type curl > /dev/null 2>&1; then
        curl -fsSL "$1" -o "$2"
        return $?
    elif type wget > /dev/null 2>&1; then
        wget -q "$1" -O "$2"
        return $?
    else
        echo "curl or wget not found"
        return 1
    fi
}

download_and_check() {
    if [ -n "$1" ]; then
        _dirname="$(dirname "$1")"
        _basename="$(basename "$1")"

        if download_file "$download_url/$_dirname/$_basename?$(date +%s)" "$tmp_file"; then
            if grep -Fq "#jas-update" "$tmp_file"; then
                if type get_script_basename > /dev/null 2>&1; then
                    _remote_basename="$(get_script_basename "$tmp_file")"

                    # If the remote file has a different name than the requested one then download the correct one instead
                    if [ "$_basename" != "$_remote_basename" ] && [ -z "$3" ]; then # third parameter to avoid loops
                        download_and_check "$_dirname/$_remote_basename" "$2" true
                        return $?
                    fi
                fi

                if [ -z "$2" ] || ! md5sum_compare "$tmp_file" "$2"; then
                    return 0 # checksums do not match or no local file to compare
                else
                    return 2 # checksums match, no update needed
                fi
            else
                echo "Downloaded file is not valid"
            fi
        fi
    else
        echo "No file specified to download"
    fi

    return 1 # download failed
}

script_trapexit() {
    rm -f "$tmp_file"
}

case "$1" in
    "setup") ;; # Prevent execution of every action except setup when not installed
    *)
        require_installed

        # Only allow one instance of this script to be running
        lockfile check && echo "Only one instance of this script is allowed, waiting..."
        lockfile lockwait
    ;;
esac

case "$1" in
    "start")
        if [ ! -f "$check_file" ]; then
            date "+%Y-%m-%d %H:%M:%S" > "$check_file"
            [ -z "$IS_INTERACTIVE" ] && export JAS_BOOT=1 # Assume started by system when non-interactive
        fi

        # If custom-configs script is available add 'jas' alias to profile.add
        if execute_script_basename "custom-configs.sh" check; then
            if [ ! -f /jffs/configs/profile.add ] || ! grep -Fq "alias jas=" /jffs/configs/profile.add; then
                mkdir -p /jffs/configs
                echo "alias jas='$script_path'" >> /jffs/configs/profile.add
            fi
        fi

        [ -z "$IS_INTERACTIVE" ] && logger -t "$script_name" "Starting scripts ($SCRIPTS_DIR)..."
        echo "Starting scripts (${fwe}$SCRIPTS_DIR${frt})..."

        scripts_action start
    ;;
    "stop")
        [ -z "$IS_INTERACTIVE" ] && logger -t "$script_name" "Stopping scripts ($SCRIPTS_DIR)..."
        echo "Stopping scripts (${fwe}$SCRIPTS_DIR${frt})..."

        scripts_action stop
        [ -f "$check_file" ] && rm -f "$check_file"
    ;;
    "restart")
        [ -z "$IS_INTERACTIVE" ] && logger -t "$script_name" "Restarting scripts ($SCRIPTS_DIR)..."
        echo "Restarting scripts (${fwe}$SCRIPTS_DIR${frt})..."

        scripts_action restart
    ;;
    "exec")
        if [ -z "$2" ]; then
            echo "Usage: ${fwe}$0 $1 <name>${frt}"
            exit 1
        fi

        name="$(basename "$2" .sh)"

        if [ -f "$SCRIPTS_DIR/${name}.sh" ]; then
            shift
            shift
            lockfile unlock
            exec /bin/sh "$SCRIPTS_DIR/${name}.sh" "$@"
        else
            echo "Not found: ${fwe}${name}${frt}"
            exit 1
        fi
    ;;
    "status")
        echo "Directory: ${fwe}${SCRIPTS_DIR}${frt}"

        status="${frd}not started${frt}"
        [ -f "$check_file" ] && status="${fgn}started${frt}"
        echo "Status: $status"
        echo

        for entry in "$SCRIPTS_DIR"/*.sh; do
            entry="$(readlink -f "$entry")"
            [ "$entry" = "$script_path" ] && continue # ignore self
            ! grep -q "#jas-update\|#jas-custom" "$entry" && continue # ignore scripts without jas-update or jas-custom tag

            basename="$(basename "$entry" .sh)"
            [ "$basename" = "common" ] && continue # ignore common.sh script

            state="${frd}disabled"
            [ -x "$entry" ] && state="${fgn}enabled"
            crontab_entry check "$basename" && state="$state ${fyw}cron"
            [ -f "$SCRIPTS_DIR/$basename.conf" ] && state="$state ${fcn}config"

            printf "%s%-20s %-20s %s\n" "$fwe" "$basename" "$state" "$frt"
        done
    ;;
    "install"|"remove"|"enable"|"disable")
        if [ -z "$2" ]; then
            echo "Usage: ${fwe}$0 $1 <name>${frt}"
            exit 1
        fi

        action="$1"
        shift

        if [ "$action" = "install" ] && [ "$BRANCH" != "master" ]; then
            echo "Using branch: ${fwe}$BRANCH${frt}"
        fi

        for arg in "$@"; do
            name=$(echo "$arg" | cut -d '.' -f 1)
            colored="${fwe}${name}${frt}"

            case "$action" in
                "install")
                    printf "Downloading '%s' script... " "$colored"

                    if download_and_check "scripts/${name}.sh"; then
                        cat "$tmp_file" > "$SCRIPTS_DIR/${name}.sh"
                        chmod +x "$SCRIPTS_DIR/${name}.sh"

                        echo "${fcn}success!${frt}"
                    else
                        failure=true
                    fi
                ;;
                "remove")
                    if [ -f "$SCRIPTS_DIR/${name}.sh" ]; then
                        /bin/sh "$SCRIPTS_DIR/${name}.sh" stop
                        rm "$SCRIPTS_DIR/${name}.sh"
                        echo "Removed: $colored"
                    else
                        echo "Not found: $colored"
                        failure=true
                    fi
                ;;
                "enable")
                    if [ ! -f "$SCRIPTS_DIR/${name}.sh" ]; then
                        echo "Not found: $colored"
                        failure=true
                    elif [ ! -x "$SCRIPTS_DIR/${name}.sh" ]; then
                        chmod +x "$SCRIPTS_DIR/${name}.sh"
                        echo "Enabled: $colored"
                    else
                        echo "Already enabled: $colored"
                        failure=true
                    fi
                ;;
                "disable")
                    if [ ! -f "$SCRIPTS_DIR/${name}.sh" ]; then
                        echo "Not found: $colored"
                        failure=true
                    elif [ -x "$SCRIPTS_DIR/${name}.sh" ]; then
                        /bin/sh "$SCRIPTS_DIR/${name}.sh" stop
                        chmod -x "$SCRIPTS_DIR/${name}.sh"
                        echo "Disabled: $colored"
                    else
                        echo "Already disabled: $colored"
                        failure=true
                    fi
                ;;
            esac
        done

        [ -n "$failure" ] && exit 1
    ;;
    "update")
        if [ ! -f "$SCRIPTS_DIR/common.sh" ]; then
            echo "Required script '${fwe}common.sh${frt}' not found in '${fwe}$SCRIPTS_DIR${frt}', maybe run '${fwe}$0 setup${frt}' ?"
            exit 1
        fi

        if [ "$BRANCH" != "master" ]; then
            echo "Using branch: ${fwe}$BRANCH${frt}"
        fi

        for entry in "$SCRIPTS_DIR/common.sh" "$SCRIPTS_DIR"/*.sh; do
            entry="$(readlink -f "$entry")"
            [ "$entry" = "$script_path" ] && continue # ignore self
            ! grep -Fq "#jas-update" "$entry" && continue # ignore scripts without jas-update tag

            basename="$(basename "$entry")" # local file name
            remote_basename="$(get_script_basename "$entry")" # remote file name

            if [ "$basename" = "common.sh" ]; then
                [ -n "$common_updated" ] && continue
                common_updated=true
            fi

            printf "%s " "${fwe}$basename${frt}"

            output="$(download_and_check "scripts/$remote_basename" "$entry")"
            status=$?

            if [ "$status" -eq 0 ]; then
                cat "$tmp_file" > "$entry"
                printf "%s!! updated%s" "$fcn" "$frt"
            elif [ "$status" -eq 2 ]; then
                printf "%s✓%s" "$fgn" "$frt"
            else
                printf "%s✗ %s%s" "$frd" "$output" "$frt"
            fi

            printf "\n";

            # Perform self update right after common.sh
            if [ "$SELF_UPDATE" = true ] && [ "$basename" = "common.sh" ]; then
                printf "%s " "${fwe}$(basename "$0")${frt}"

                remote_basename="$(get_script_basename "$script_path")" # remote file name
                output="$(download_and_check "$remote_basename" "$script_path")"
                status=$?

                if [ "$status" -eq 0 ]; then
                    # hacky way to avoid issues while running script that has changed on disk
                    { sleep 1 && cat "$tmp_file" > "$script_path"; rm -f "$tmp_file"; } &

                    printf "%s! updated - please re-run!%s\n" "$fcn" "$frt"
                    exit 0
                elif [ "$status" -eq 2 ]; then
                    printf "%s✓%s" "$fgn" "$frt"
                else
                    printf "%s✗ %s%s" "$frd" "$output" "$frt"
                fi

                printf "\n"
            fi
        done
    ;;
    "config")
        if [ -z "$2" ]; then
            echo "Usage: ${fwe}$0 $1 <name>${frt}"
            exit 1
        fi

        name=$(echo "$2" | cut -d '.' -f 1)

        # No support to edit jas.conf is deliberate as the only thing it should contain is SCRIPTS_DIR
        if [ -f "$SCRIPTS_DIR/${name}.sh" ]; then
            if [ -z "$EDITOR" ]; then # Try to use one of the popular editors if $EDITOR is not set
                if type nano > /dev/null 2>&1; then
                    export EDITOR="nano"
                elif type vim > /dev/null 2>&1; then
                    export EDITOR="vim"
                elif type vi > /dev/null 2>&1; then
                    export EDITOR="vi"
                fi
            fi

            if [ -n "$EDITOR" ]; then
                if [ -f "$SCRIPTS_DIR/${name}.conf" ]; then # If the file already exists edit it directly
                    $EDITOR "$SCRIPTS_DIR/${name}.conf"
                else # If the files doesn't exist edit temporary file
                    rm -f "$tmp_file"

                    if grep -q "^load_script_config" "$SCRIPTS_DIR/${name}.sh"; then
                        sed -ne '/readonly common_script/,$p' -e '/load_script_config/q' "$SCRIPTS_DIR/${name}.sh" | grep -E '^(#|[A-Z0-9_]+=.*#.*$)' | sed -e 's/ # /     # /g' -e 's/^#*/#/g' > "$tmp_file"
                    fi

                    if [ ! -f "$tmp_file" ] || [ ! -s "$tmp_file" ]; then
                        echo "${fwe}No configuration options are available for this script.${frt}"
                        exit 0
                    fi

                    $EDITOR "$tmp_file"

                    # Save the file if it contains valid content
                    if grep -v '^[[:space:]]*#' "$tmp_file" | grep -v '^[[:space:]]*$' > /dev/null; then
                        echo "Saving configuration file: ${fwe}$SCRIPTS_DIR/${name}.conf${frt}"
                        mv -f "$tmp_file" "$SCRIPTS_DIR/${name}.conf"
                    else # otherwise discard it
                        echo "File contains no valid content, not saving."
                        exit 1
                    fi
                fi
            else
                echo "Please set the ${fwe}EDITOR${frt} variable in the environment or config."
                exit 1
            fi
        else
            echo "Not found: ${fwe}${name}${frt}"
            exit 1
        fi
    ;;
    "setup")
        set -e

        [ ! -x "$0" ] && chmod +x "$0"
        #shellcheck disable=SC2174
        [ ! -d "$SCRIPTS_DIR" ] && mkdir -pvm 755 "$SCRIPTS_DIR"

        if [ ! -f "$SCRIPTS_DIR/common.conf" ]; then
            cat <<EOT > "$SCRIPTS_DIR/common.conf"
# You can override configuration variables from jas.sh and common.sh here

# Uncomment to use 'develop' branch when installing or updating scripts
#BRANCH="develop"

EOT
        fi

        if [ ! -f "$SCRIPTS_DIR/common.sh" ]; then
            printf "Downloading shared dependency script... "

            if ! download_and_check "scripts/common.sh"; then
                exit 1
            fi

            cat "$tmp_file" > "$SCRIPTS_DIR/common.sh"
            rm -f "$tmp_file"
            echo "ok!"

            exec /bin/sh "$script_path" setup
        fi

        [ -z "$JAS_COMMON" ] && { echo "Shared dependency script is not loaded, cannot continue!"; exit 1; }

        if is_merlin_firmware; then
            write_to_script=/jffs/scripts/services-start
        else
            write_to_script=/jffs/scripts/usb-mount-script

            # Do not run this check if user is using the workaround already
            if [ ! -f /jffs/scripts/usb-mount-script ]; then
                nvram_script="/bin/sh $script_path start"
                current_value="$(nvram get script_usbmount)"

                if [ "$current_value" = "$nvram_script" ]; then
                    echo "NVRAM variable '${fwe}script_usbmount${frt}' is already set to '${fwe}$nvram_script${frt}'"
                    write_to_script=
                elif [ -z "$current_value" ]; then
                    echo "Setting NVRAM variable '${fwe}script_usbmount${frt}' to '${fwe}$nvram_script${frt}'"

                    nvram set script_usbmount="$nvram_script"

                    echo "${fwe}Waiting 15 seconds to verify that the value is not getting erased...${frt}"
                    sleep 15

                    if [ -z "$(nvram get script_usbmount)" ]; then
                        cat <<EOT

${fyw}Value has been cleaned by the router - you will have to use a workaround:${frt}
${fcn}https://github.com/jacklul/asuswrt-scripts/tree/master/asusware-usb-mount-script${frt}

EOT

                        #shellcheck disable=SC3045
                        read -rp "${fwe}Do you wish to install the workaround now ?${frt} [y/N] " response

                        case "$response" in
                            [Yy]*|[Yy][Ee][Ss]*) 
                                echo # insert empty line after prompt

                                if download_file "$download_url/asusware-usb-mount-script/asusware-usb-mount-script.sh" /tmp/asusware-usb-mount-script.sh; then
                                    if ! sh /tmp/asusware-usb-mount-script.sh "$BRANCH"; then
                                        cat <<EOT

${frd}Workaround installation failed!${frt}
If you wish to re-run the installer execute: '${fwe}sh /tmp/asusware-usb-mount-script.sh${frt}'

EOT
                                    fi
                                else
                                    echo "${frd}Failed to download the installer, you will have to install manually!${frt}"
                                fi
                            ;;
                        esac
                    else # no workaround needed
                        nvram commit
                        write_to_script=
                    fi
                else # do not touch if the variable is already set
                    echo "NVRAM variable '${fwe}script_usbmount${frt}' is set to '${fwe}$current_value${frt}', not touching it!"
                    echo "You will have to make sure that '${fwe}$nvram_script${frt}' command also runs on USB mount!"
                    write_to_script=
                fi
            fi
        fi

        if [ -n "$write_to_script" ]; then
            if [ ! -f "$write_to_script" ]; then
                echo "Creating '${fwe}$write_to_script${frt}'..."

                cat <<EOT > "$write_to_script"
#!/bin/sh

EOT
                chmod +x "$write_to_script"
            fi

            if ! grep -Fq "$script_path" "$write_to_script"; then
                echo "Adding this script to '${fwe}$write_to_script${frt}'..."

                echo "( $script_path start ) # https://github.com/jacklul/asuswrt-scripts" >> "$write_to_script"
            else
                echo "Script line already exists in '${fwe}$write_to_script${frt}'"
            fi
        fi

        # Migrate old scripts
        for entry in "$script_dir"/*.sh; do
            entry="$(readlink -f "$entry")"
            [ "$entry" = "$script_path" ] && continue # ignore self
            ! grep -Fq "#jacklul-asuswrt-scripts-update" "$entry" && continue # ignore scripts without old tag

            name="$(basename "$entry" .sh)"
            { [ "$name" = "scripts-startup" ] || [ "$name" = "update-scripts" ] ; } && continue # ignore deprecated scripts

            echo "Moving '${fwe}$entry${frt}' to '${fwe}$SCRIPTS_DIR/${name}.sh${frt}'"

            mv "$entry" "$SCRIPTS_DIR/${name}.sh"
            sed 's/#jacklul-asuswrt-scripts-update=/#jas-update=/g' -i "$SCRIPTS_DIR/${name}.sh"
            [ -f "$script_dir/${name}.conf" ] && mv "$script_dir/${name}.conf" "$SCRIPTS_DIR/${name}.conf"
            migrated=true
        done

        if [ -f "$script_dir/scripts-startup.sh" ] || [ -f "$script_dir/update-scripts.sh" ]; then
            echo "Scripts '${fwe}scripts-startup.sh${frt}' and '${fwe}update-scripts.sh${frt}' are deprecated and can be removed!"
        fi

        if [ -n "$migrated" ]; then
            echo "Running '${fwe}$0 update${frt}':"

            /bin/sh "$script_path" update
        fi

        echo "${fgn}Setup finished!${frt}"
    ;;
    *)
        name="$(basename "$1" .sh)"

        if [ -f "$SCRIPTS_DIR/${name}.sh" ]; then
            shift
            lockfile unlock
            exec /bin/sh "$SCRIPTS_DIR/${name}.sh" "$@"
        fi

        cat <<EOT
${fwe}github.com/${fcn}j${fwe}acklul/${fcn}a${fwe}suswrt-${fcn}s${fwe}cripts${frt}

Usage: ${fwe}$0 <action> <args> ...${frt}

Available actions:
 ${fwe}start       ${frt}- start all scripts
 ${fwe}stop        ${frt}- stop all scripts
 ${fwe}restart     ${frt}- restart all scripts
 ${fwe}exec        ${frt}- execute a script, with args
 ${fwe}status      ${frt}- prints status of all scripts
 ${fwe}config      ${frt}- edit configuration file of a script
 ${fwe}update      ${frt}- update all scripts
 ${fwe}install     ${frt}- install script(s)
 ${fwe}remove      ${frt}- remove script(s)
 ${fwe}enable      ${frt}- enable script(s)
 ${fwe}disable     ${frt}- disable script(s)
 ${fwe}setup       ${frt}- initial setup

EOT

        exit 1
    ;;
esac
