#!/bin/sh
# Made by Jack'lul <jacklul.github.io>
#
# Update all installed scripts
#
# For security and reliability reasons this cannot be run at boot
#

#jacklul-asuswrt-scripts-update=update-scripts.sh
#shellcheck disable=SC2155

readonly script_path="$(readlink -f "$0")"
readonly script_name="$(basename "$script_path" .sh)"
readonly script_dir="$(dirname "$script_path")"
readonly script_config="$script_dir/$script_name.conf"

BRANCH="master" # which git branch to use
BASE_URL="https://raw.githubusercontent.com/jacklul/asuswrt-scripts" # base download url, no ending slash!
BASE_PATH="scripts" # base path to scripts directory in the download URL, no slash on either side
AUTOUPDATE=true # whenever to auto-update this script first or not

if [ -f "$script_config" ]; then
    #shellcheck disable=SC1090
    . "$script_config"
fi

download_url="$BASE_URL/$BRANCH/$BASE_PATH"
curl_binary="curl"
[ -f /opt/bin/curl ] && curl_binary="/opt/bin/curl" # prefer Entware's curl as it is not modified by Asus

md5_compare() {
    { [ ! -f "$1" ] || [ ! -f "$2" ] ; } && return 1

    if [ -n "$1" ] && [ -n "$2" ]; then
        if [ "$(md5sum "$1" 2> /dev/null | awk '{print $1}')" = "$(md5sum "$2" 2> /dev/null | awk '{print $1}')" ]; then
            return 0
        fi
    fi

    return 1
}

download_and_check() {
    if [ -n "$1" ] && [ -n "$2" ]; then
        if $curl_binary -fsSL "$1?$(date +%s)" -o "/tmp/$script_name-download"; then
            if ! md5_compare "/tmp/$script_name-download" "$2"; then
                return 0
            fi
        else
            echo "failed to download '$1'"
        fi
    fi

    return 1
}

if [ -z "$1" ] || [ "$1" = "run" ]; then
    if [ "$AUTOUPDATE" = true ]; then
        basename="$(basename "$script_path")"

        target_basename="$(grep -E '^#(\s+)?jacklul-asuswrt-scripts-update=' "$script_path" | sed 's/.*jacklul-asuswrt-scripts-update=//')"
        [ -n "$target_basename" ] && basename=$target_basename

        if download_and_check "$download_url/$basename" "$script_path"; then
            # hacky but works
            { sleep 1 && cat "/tmp/$script_name-download" > "$script_path"; } &

            echo "Script has been updated, please re-run!"
            exit 0
        fi
    fi

    trap 'rm -f "/tmp/$script_name-download"; exit $?' EXIT

    for entry in "$script_dir"/*.sh; do
        entry="$(readlink -f "$entry")"
        basename="$(basename "$entry")"

        [ "$entry" = "$script_path" ] && continue
        ! grep -q "jacklul-asuswrt-scripts-update" "$entry" && continue

        target_basename="$(grep -E '^#(\s+)?jacklul-asuswrt-scripts-update=' "$entry" | sed 's/.*jacklul-asuswrt-scripts-update=//')"
        [ -n "$target_basename" ] && basename=$target_basename

        if [ -n "$target_basename" ]; then
            printf "Processing '%s' (%s)... " "$entry" "$basename"
        else
            printf "Processing '%s'... " "$entry"
        fi

        if download_and_check "$download_url/$basename" "$entry"; then
            cat "/tmp/$script_name-download" > "$entry"
            printf "updated!"
        fi

        printf "\n";
    done
fi
