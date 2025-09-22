#!/bin/sh
# This script allows reordering of VPNC Fusion profiles
#
# Warning: This script changes order of the profiles without modifying 
# idx identifier of the profile, this doesn't seem to break anything on 
# 3.0.0.4.388_25210 firmware but it might cause issues on older versions.
#

#shellcheck disable=SC3037,SC3045

[ ! -t 0 ] && { echo "This script requires a terminal to run"; exit 1; }

vpnc_clientlist="$(nvram get vpnc_clientlist)"

if [ ! -f /tmp/vpnc_clientlist.bak ]; then
    echo "$vpnc_clientlist" > /tmp/vpnc_clientlist.bak && echo "Current value of 'vpnc_clientlist' saved to /tmp/vpnc_clientlist.bak"
    echo
fi

list="$(echo "$vpnc_clientlist" | tr '<' '\n')"

while true; do
    lines=0
    i=1
    IFS="$(printf '\n\b')"
    for line in $list; do
        profile_name="$(echo "$line" | awk -F '>' '{print $1, "("$2")", "["$7"]"}')"

        if [ "$i" = "$j" ]; then
            echo "$i) >> $profile_name <<"
        else
            echo "$i) $profile_name"
        fi

        i=$((i + 1))
    done
    lines=$((i + 1))

    echo
    if [ -n "$j" ]; then
        echo "u) Move up"
        echo "d) Move down"

        lines=$((lines + 2))
    fi

    echo "s) Save$([ -n "$saved" ] && echo "d OK!")"
    echo "q) Quit"
    lines=$((lines + 2))
    saved=

    read -rp "Selection: " choice
    case "$choice" in
        *[0-9]*)
            [ "$choice" != "$j" ] && j=$choice || j=""
        ;;
        u|U)
            if [ "$j" -gt 1 ]; then
                line_to_move="$(echo "$list" | sed -n "${j}p")"
                line_above="$(echo "$list" | sed -n "$((j - 1))p")"
                list="$(echo "$list" | awk -v line="$j" -v prev=$((j-1)) -v ltm="$line_to_move" -v la="$line_above" 'NR==prev{print ltm; next}NR==line{print la; next}{print}')"
                j=$((j - 1))
            fi
        ;;
        d|D)
            if [ "$j" -lt "$(echo "$list" | wc -l)" ]; then
                line_to_move="$(echo "$list" | sed -n "${j}p")"
                line_below="$(echo "$list" | sed -n "$((j + 1))p")"
                list="$(echo "$list" | awk -v line="$j" -v prev=$((j+1)) -v ltm="$line_to_move" -v la="$line_below" 'NR==prev{print ltm; next}NR==line{print la; next}{print}')"
                j=$((j + 1))
            fi
        ;;
        s|S)
            new="$(echo "$list" | tr '\n' '<' | sed 's/<$//')"

            if [ "$new" != "$vpnc_clientlist" ]; then
                nvram set vpnc_clientlist="$new"
                nvram commit
                saved=true
            fi
        ;;
        q|Q)
            exit 0
        ;;
    esac

    printf "\033[%dA\033[J" "$lines"
done
