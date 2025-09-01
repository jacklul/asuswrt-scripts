#!/bin/sh
# Made by Jack'lul <jacklul.github.io>
#
# This script is here just to switch it to the legacy branch
#

#jacklul-asuswrt-scripts-update=update-scripts.sh
#shellcheck disable=SC2155

readonly script_path="$(readlink -f "$0")"
readonly script_name="$(basename "$script_path" .sh)"

curl_binary="curl"
[ -f /opt/bin/curl ] && curl_binary="/opt/bin/curl"

if [ -z "$1" ] || [ "$1" = "run" ]; then
   if $curl_binary -fsSL "https://raw.githubusercontent.com/jacklul/asuswrt-scripts/legacy/scripts/update-scripts.sh" -o "/tmp/$script_name-download"; then
        { sleep 1 && cat "/tmp/$script_name-download" > "$script_path"; rm -f "/tmp/$script_name-download"; } &

        echo "This script has been updated, please re-run!"
        exit 0
    fi
fi
