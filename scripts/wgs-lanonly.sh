#!/bin/sh
# Made by Jack'lul <jacklul.github.io>
#
# This script has been renamed to wgs-lan-only.sh
#
# @TODO Remove after some time
#

#jas-update=wgs-lan-only.sh
#shellcheck disable=SC2155
#shellcheck source=./common.sh
readonly common_script="$(dirname "$0")/common.sh"
if [ -f "$common_script" ]; then . "$common_script"; else { echo "$common_script not found" >&2; exit 1; } fi

execute_script_basename "wgs-lan-only.sh" "$@"
