#!/bin/sh
# Made by Jack'lul <jacklul.github.io>
#
# Modifies CPU affinity mask of cron process making scheduled tasks less likely to interfere with router operations
#

#jacklul-asuswrt-scripts-update
#shellcheck disable=SC2155,SC2009

readonly SCRIPT_PATH="$(readlink -f "$0")"
readonly SCRIPT_NAME="$(basename "$SCRIPT_PATH" .sh)"
readonly SCRIPT_DIR="$(dirname "$SCRIPT_PATH")"
readonly SCRIPT_CONFIG="$SCRIPT_DIR/$SCRIPT_NAME.conf"
readonly SCRIPT_TAG="$(basename "$SCRIPT_PATH")"

CUSTOM_AFFINITY="" # CPU affinity mask (e.g. 2,3,4,5), when left empty it will substract 1 from init's affinity mask

if [ -f "$SCRIPT_CONFIG" ]; then
    #shellcheck disable=SC1090
    . "$SCRIPT_CONFIG"
fi

if [ -z "$CUSTOM_AFFINITY" ]; then
	INIT_AFFINITY="$(taskset -p 1 | sed 's/.*: //')"

	if echo "$INIT_AFFINITY" | grep -Eq '^[0-9]+$'; then
		CUSTOM_AFFINITY=$((INIT_AFFINITY - 1))
	fi
fi

set_affinity() {
    [ -z "$2" ] && { echo "You must specify an affinity mask"; exit 1; }

	for PID in $(pidof crond); do
		BINARY_PATH="$(readlink -f "/proc/$PID/exe")"

		case "$BINARY_PATH" in
			/opt/*)
				continue
			;;
			*)
				PID_AFFINITY="$(taskset -p "$PID" | sed 's/.*: //')"

				if [ "$1" = "unset" ] && [ -n "$INIT_AFFINITY" ]; then
					CUSTOM_AFFINITY=$INIT_AFFINITY
				fi

				if [ -n "$CUSTOM_AFFINITY" ] && [ "$PID_AFFINITY" -ne "$CUSTOM_AFFINITY" ]; then
					taskset -p "$CUSTOM_AFFINITY" "$PID" >/dev/null

					logger -st "$SCRIPT_TAG" "Changed CPU affinity mask of crond (PID $PID) to $CUSTOM_AFFINITY"
				fi
			;;
		esac
	done
}

case $1 in
	"run")
		set_affinity set "$CUSTOM_AFFINITY"
	;;
    "start")
		[ ! -f /usr/bin/taskset ] && { logger -st "$SCRIPT_TAG" "Command 'taskset' not found"; exit 1; }

		if [ -x "$SCRIPT_DIR/cron-queue.sh" ]; then
			sh "$SCRIPT_DIR/cron-queue.sh" add "$SCRIPT_NAME" "$SCRIPT_PATH run"
		else
			cru a "$SCRIPT_NAME" "*/1 * * * * $SCRIPT_PATH run"
		fi

		set_affinity set "$CUSTOM_AFFINITY"
    ;;
    "stop")
        cru d "$SCRIPT_NAME"
		set_affinity unset "$CUSTOM_AFFINITY"
    ;;
    "restart")
        sh "$SCRIPT_PATH" stop
        sh "$SCRIPT_PATH" start
    ;;
    *)
        echo "Usage: $0 run|start|stop|restart"
        exit 1
    ;;
esac
