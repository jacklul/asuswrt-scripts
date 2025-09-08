#!/bin/sh
# Made by Jack'lul <jacklul.github.io>
#
# This script has been renamed to uptime-reboot.sh
#

#jas-update=uptime-reboot.sh
#shellcheck disable=SC2155
#shellcheck source=./common.sh
readonly common_script="$(dirname "$0")/common.sh"
if [ -f "$common_script" ]; then . "$common_script"; else { echo "$common_script not found"; exit 1; } fi

execute_script_basename "uptime-reboot.sh" "$@"
