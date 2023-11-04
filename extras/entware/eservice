#!/bin/sh

SERVICE="$1"
ACTION="$2"
CALLER="$(basename "$0" .sh)"
[ -z "$SERVICE" ] && { echo "Service not specified"; exit 1; }
[ -z "$ACTION" ] && { echo "Action not specified"; exit 1; }

for FILE in $(/opt/bin/find /opt/etc/init.d/ -perm '-u+x' -name 'S*'); do
	FILE_CHECK="$(basename "$FILE")"
	MAX=4
	while [ "$MAX" -gt "0" ]; do
	    FILE_CHECK="$(echo "$FILE_CHECK" | cut -c2-)"

	    if [ "$FILE_CHECK" = "$SERVICE" ]; then
			case "$FILE" in
				S* | *.sh )
					trap "" INT QUIT TSTP EXIT
					#shellcheck disable=SC1090,SC2240
					. "$FILE" "$ACTION" "$CALLER"
				;;
				*)
					"$FILE" "$ACTION" "$CALLER"
				;;
			esac

			exit
		fi

		MAX=$((MAX-1))
	done
done

echo "Service \"$SERVICE\" not found"
