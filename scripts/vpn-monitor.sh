#!/bin/sh
# Made by Jack'lul <jacklul.github.io>
#
# Monitor VPN connections and reconnect in case of connection failure
# Optionally rotate through a defined list of servers for each reconnection
#
# Based on:
#  https://github.com/ViktorJp/VPNMON-R3/blob/main/vpnmon-r3.sh
#

#jas-update=vpn-monitor.sh
#shellcheck disable=SC2155
#shellcheck source=./common.sh
readonly common_script="$(dirname "$0")/common.sh"
if [ -f "$common_script" ]; then . "$common_script"; else { echo "$common_script not found" >&2; exit 1; } fi

# To use server rotation feature you must create /jffs/scripts/jas/vpn-monitor-<unit>.list file(s)
# To identify VPN units run 'jas vpn-monitor identify'
#
# Example line in /jffs/scripts/jas/vpn-monitor-wg5.list:
# 11.22.33.44,51820,10.2.0.2/32,IF_PRIVATE_KEY,PEER_PUBLIC_KEY,PSK
# (format: 'ep_addr,ep_port,addr,priv,ppub,psk', psk is optional)
# This is NOT compatible with lists created for VPNMON
#
# Example line in /jffs/scripts/jas/vpn-monitor-ovpn5.list:
# 11.22.33.44,1194
# (format: 'addr,port', port is optional)
# This is compatible with lists created for VPNMON
# 

TEST_PING="1.1.1.1" # IP address to ping, leave empty to skip this check
TEST_PING_LIMIT=300 # max ping time in ms, if ping is higher than this it marks ping test as failed, set to empty to disable
TEST_URL="https://ipecho.net/plain" # URL for fetch check, leave empty to skip this check
TEST_RETRIES=3 # number of retries for connectivity test, it is considered failed if all retries fail
RESTART_LIMIT=5 # limit number of restarts per unit, 0 means no limit, counter resets on successful connectivity check
ROTATE_SERVERS=false # will rotate through server list on each reconnect when enabled (appropriate .list file must exist)
ROTATE_RANDOM=false # select random address from the list instead of rotating sequentially
RESET_ON_START=false # reset all profiles to first server on the list when script is started/restarted
CRON="*/1 * * * *" # how often to run the connectivity checks, schedule as cron string, by default every minute
EXECUTE_COMMAND="" # execute a command after connection is restarted (receives arguments: $1 = unit - ovpnX/wgX, $2 = new server address or empty if not changed)

load_script_config

state_file="$TMP_DIR/$script_name"

[ -z "$TEST_RETRIES" ] && TEST_RETRIES=1 # this cannot be empty, set to the lowest possible value
[ -z "$RESTART_LIMIT" ] && RESTART_LIMIT=0 # this cannot be empty, set to 0 (no limit)

script_trapexit() {
    ip rule del prio 55 > /dev/null 2>&1
    [ -n "$nvram_commit" ] && nvram commit
}

restart_counter() {
    if [ "$RESTART_LIMIT" -eq 0 ]; then
        return
    fi

    _state_file="$state_file-$2.tmp"
    _counter=0

    if [ -f "$_state_file" ]; then
        _counter="$(cat "$_state_file")"
        ! echo "$_counter" | grep -qE '^[0-9]+$' && _counter=0
    fi

    case "$1" in
        "increment")
            _counter=$((_counter+1))
            echo "$_counter" > "$_state_file"
        ;;
        "check")
            if [ "$_counter" -gt "$RESTART_LIMIT" ]; then
                return 1
            fi

            if [ "$RESTART_LIMIT" -gt 0 ] && [ "$_counter" -eq "$RESTART_LIMIT" ]; then
                restart_counter increment "$2"
                logecho "Restart limit of $RESTART_LIMIT reached for $2" error
                return 1
            fi

            return 0
        ;;
        "get")
            echo "$_counter"
        ;;
        "reset")
            rm -f "$state_file-$2.tmp"
        ;;
    esac
}

restart_connection_by_ifname() {
    _type=
    _reset=
    _is_active=

    if [ "$(echo "$1" | cut -c 1-3)" = "wgc" ]; then # WireGuard
        _type="WireGuard"
        _id=$(echo "$1" | cut -c 4-)
        _unit="wg${_id}"
        _file="$script_dir/$script_name-wg${_id}.list"
        _nvram_addr="wgc${_id}_ep_addr"
        _service="wgc ${_id}"
    elif [ "$(echo "$1" | cut -c 1-4)" = "tun1" ] || [ "$(echo "$1" | cut -c 1-4)" = "tap1" ]; then # OpenVPN
        _type="OpenVPN"
        _id=$(echo "$1" | cut -c 5-)
        _unit="ovpn${_id}"
        _file="$script_dir/$script_name-ovpn${_id}.list"
        _nvram_addr="vpn_client${_id}_addr"
        _service="vpnclient${_id}"
    fi

    [ "$2" = "reset" ] && _reset=true

    if interface_exists "$1"; then
        _is_active=true
    fi

    if [ "$ROTATE_SERVERS" = true ] && [ -f "$_file" ]; then
        _total="$(cat "$_file" | grep -cv '^\(#\|\s*$\)')"

        if [ -z "$_total" ] || [ "$_total" -eq 0 ]; then
            return 1
        fi

        if [ -z "$_reset" ]; then
            if [ "$ROTATE_RANDOM" = true ]; then
                _rand=$(awk 'BEGIN {srand(); print int(32768 * rand())}')
                _next=$((_rand%_total+1))
            else
                _current="$(nvram get "$_nvram_addr")"
                _last=$(grep -v '^\(#\|\s*$\)' "$_file" | grep -n "$_current" | head -n 1 | cut -d: -f1)
                [ -z "$_last" ] && _last=0
                _next=$((_last+1))
                [ "$_next" -gt "$_total" ] && _next=1
            fi
        else
            _next=1
        fi

        _line="$(grep -v '^\(#\|\s*$\)' "$_file" | sed -ne "${_next}p" -e 's/\r\n\|\n//g')"

        if [ "$_type" = "WireGuard" ]; then
            _cur_ep_addr="$(nvram get "wgc${_id}_ep_addr")"

            # This is NOT compatible with lists created for VPNMON
            _new_ep_addr="$(echo "$_line" | cut -d ',' -f 1)"
            _new_ep_port="$(echo "$_line" | cut -d ',' -f 2)"
            _new_addr="$(echo "$_line" | cut -d ',' -f 3)"
            _new_priv="$(echo "$_line" | cut -d ',' -f 4)"
            _new_ppub="$(echo "$_line" | cut -d ',' -f 5)"
            _new_psk="$(echo "$_line" | cut -d ',' -f 6)"

            [ "$_cur_ep_addr" = "$_new_ep_addr" ] && return 0 # no change

            nvram set "wgc${_id}_addr=$_new_addr"
            nvram set "wgc${_id}_ep_addr=$_new_ep_addr"
            nvram set "wgc${_id}_ep_addr_r=$_new_ep_addr"
            nvram set "wgc${_id}_ep_port=$_new_ep_port"
            nvram set "wgc${_id}_priv=$_new_priv"
            nvram set "wgc${_id}_ppub=$_new_ppub"
            nvram set "wgc${_id}_psk=$_new_psk"

            _new_addr="$_new_ep_addr:$_new_ep_port"
        elif [ "$_type" = "OpenVPN" ]; then
            _cur_addr="$(nvram get "vpn_client${_id}_addr")"

            # This is compatible with lists created for VPNMON
            _new_addr="$(echo "$_line" | cut -d ',' -f 1)"
            _new_port="$(echo "$_line" | cut -d ',' -f 2)"

            [ "$_cur_addr" = "$_new_addr" ] && return 0 # no change

            nvram set "vpn_client${_id}_addr=$_new_addr"

            if [ -n "$_new_port" ]; then
                nvram set "vpn_client${_id}_port=$_new_port"
            else
                _new_port="$(nvram get "vpn_client${_id}_port")"
            fi

            _new_addr="$_new_addr:$_new_port"
        fi

        if [ -n "$_new_addr" ]; then
            nvram_commit=true # mark that we need to commit nvram changes on script exit

            if [ -n "$_is_active" ]; then
                service "restart_${_service}" >/dev/null 2>&1
                [ -n "$EXECUTE_COMMAND" ] && $EXECUTE_COMMAND "$_unit" "$_new_addr"

                logecho "Restarted $_type client $_id ($reason) with new server address: $_new_addr" logger
            else
                logecho "Set new server address for $_type client $_id: $_new_addr" logger
            fi
        else
            logecho "Error: Failed to set new server address for $_type client $_id" error
        fi
    elif interface_exists "$1"; then
        service "restart_${_service}" >/dev/null 2>&1
        [ -n "$EXECUTE_COMMAND" ] && $EXECUTE_COMMAND "$_unit"

        logecho "Restarted $_type client $_id ($reason)" logger
    fi
}

check_connection_by_ifname() {
    _retries="$TEST_RETRIES"
    _tun_ip=

    if [ "$(echo "$1" | cut -c 1-3)" = "wgc" ] && [ -n "$2" ]; then # $1 = ifname, $2 = vpnc idx
        _tun_ip="$(nvram get "${1}_addr" | cut -d '/' -f1)"
        ip rule add from "$_tun_ip" lookup "$2" prio 55 > /dev/null 2>&1
    fi

    _success=
    while [ "$_retries" -gt 0 ]; do
        _ping_success=
        _url_success=

        if [ -n "$TEST_PING" ]; then
            echo "Pinging $TEST_PING via $1"

            _output="$(ping -I "$1" -c 1 -W 2 "$TEST_PING" 2> /dev/null | awk -F 'time=| ms' 'NF==3{print $(NF-1)}' | sort -rn)"

            if [ -n "$_output" ]; then
                _ping_success=true

                if [ -n "$TEST_PING_LIMIT" ] && [ "$TEST_PING_LIMIT" -gt 0 ]; then
                    _ping=
                    [ -n "$_output" ] && _ping="$(awk "BEGIN {printf \"%0.0f\", ${_output}}")"

                    if [ -z "$_ping" ] || [ "$_ping" = "" ]; then
                        echo "Invalid ping output ($1): $_output" >&2
                        _ping_success=
                    fi

                    if [ "$_ping" -gt "$TEST_PING_LIMIT" ]; then
                        echo "Ping time ${_ping}ms is higher than limit of ${TEST_PING_LIMIT}ms ($1)" >&2
                        _ping_success=
                    else
                        echo "Ping time ${_ping}ms is within limit of ${TEST_PING_LIMIT}ms ($1)"
                    fi
                fi
            else
                echo "Failed to ping target ($1)" >&2
            fi
        else
            _ping_success=true
        fi

        if [ -n "$TEST_URL" ];then 
            echo "Fetching URL $TEST_URL via $1"

            if curl -sf --retry 3 --retry-delay 2 --retry-all-errors --interface "$1" "$TEST_URL" > /dev/null 2>&1; then
                _url_success=true
            else
                echo "Failed to fetch URL ($1)" >&2
            fi
        else
            _url_success=true
        fi

        if [ -n "$_ping_success" ] && [ -n "$_url_success" ]; then
            _success=true
            break
        fi

        _retries=$((_retries-1))
        sleep 1
    done

    reason=
    [ -z "$_ping_success" ] && reason="ping"
    [ -z "$_url_success" ] && reason="$(echo "$reason url" | sed 's/^ *//g')"

    [ -n "$_tun_ip" ] && ip rule del prio 55 > /dev/null 2>&1
    [ -n "$_success" ] && return 0
    return 1;
}

check_connections() {
    { [ -z "$TEST_PING" ] && [ -z "$TEST_URL" ] ; } && { logecho "Error: TEST_PING/TEST_URL is not set" error; exit 1; }
    { [ "$(nvram get wan0_state_t)" != "2" ] && [ "$(nvram get wan1_state_t)" != "2" ] ; } && { echo "WAN network is not connected" >&2; return 1; }

    _vpnc_profiles="$(get_vpnc_clientlist | awk -F '>' '{print $6, $2, $3, $7}' | grep "^1" | cut -d ' ' -f 2-)"

    _oldIFS=$IFS
    IFS="$(printf '\n\b')"
    for _entry in $_vpnc_profiles; do
        _type="$(echo "$_entry" | cut -d ' ' -f 1)"
        _id="$(echo "$_entry" | cut -d ' ' -f 2)"
        _idx="$(echo "$_entry" | cut -d ' ' -f 3)"

        if [ "$_type" = "WireGuard" ]; then
            _unit="wg${_id}"
            _iface="wgc${_id}"
        elif [ "$_type" = "OpenVPN" ]; then
            _unit="ovpn${_id}"
            _iface="$(nvram get "vpn_client${_id}_if")1${_id}"
        else
            continue
        fi

        if ! restart_counter check "$_unit"; then
            continue
        fi

        if interface_exists "$_iface" && ! check_connection_by_ifname "$_iface" "$_idx"; then
            echo "$_unit connection is DOWN ($_counter)"

            restart_connection_by_ifname "$_iface"
            restart_counter increment "$_unit"
        else
            echo "$_unit connection is OK"

            restart_counter reset "$_unit"
        fi
    done
    IFS=$_oldIFS
}

manual_restart() {
    [ -z "$1" ] && { echo "No unit provided" >&2; exit 1; }
    [ "$2" = "reset" ] && echo "Will restart using first server on the list"
    reason="manual"

    if [ "$(echo "$1" | cut -c 1-2)" = "wg" ]; then
        _id=$(echo "$1" | cut -c 3-)

        restart_connection_by_ifname "wgc${_id}" "$2"
    elif [ "$(echo "$1" | cut -c 1-4)" = "ovpn" ]; then
        _id=$(echo "$1" | cut -c 5-)
        _if="$(nvram get "vpn_client${_id}_if")"

        restart_connection_by_ifname "${_if}1${_id}" "$2"
    else
        echo "Invalid unit: $1" >&2
    fi
}

case "$1" in
    "run")
        lockfile lockexit
        check_connections
        lockfile unlock
    ;;
    "rotate")
        [ -z "$2" ] && { echo "No unit provided" >&2; exit 1; }
        lockfile lockexit rotate
        manual_restart "$2" "$3" # if $3 = "reset" will use first server from the list
        lockfile unlock rotate
    ;;
    "identify")
        printf "%-7s %-7s %-22s %-20s\n" "Unit" "Active" "Server address" "Description"
        printf "%-7s %-7s %-22s %-20s\n" "------" "------" "---------------------" "--------------------"

        IFS="$(printf '\n\b')"
        for entry in $(get_vpnc_clientlist); do
            desc="$(echo "$entry" | awk -F '>' '{print $1}')"
            type="$(echo "$entry" | awk -F '>' '{print $2}')"
            id="$(echo "$entry" | awk -F '>' '{print $3}')"
            active="$(echo "$entry" | awk -F '>' '{print $6}')"
            [ "$active" = "1" ] && active=yes || active=no

            if [ "$type" = "WireGuard" ]; then
                unit="wg${id}"
                address="$(nvram get "wgc${id}_ep_addr_r"):$(nvram get "wgc${id}_ep_port")"
            elif [ "$type" = "OpenVPN" ]; then
                unit="ovpn${id}"
                address="$(nvram get "vpn_client${id}_addr"):$(nvram get "vpn_client${id}_port")"
            else
                continue
            fi

            printf "%-7s %-7s %-22s %-50s\n" "$unit" "$active" "$address" "$desc"
        done
    ;;
    "start")
        crontab_entry add "$CRON $script_path run"

        if [ "$RESET_ON_START" = true ]; then
            oldIFS=$IFS
            IFS="$(printf '\n\b')"
            for entry in $(get_vpnc_clientlist | awk -F '>' '{print $2, $3}'); do
                type="$(echo "$entry" | cut -d ' ' -f 1)"
                id="$(echo "$entry" | cut -d ' ' -f 2)"

                if [ "$type" = "WireGuard" ]; then
                    unit="wg${id}"
                elif [ "$type" = "OpenVPN" ]; then
                    unit="ovpn${id}"
                else
                    continue
                fi

                if [ -f "$script_dir/$script_name-${unit}.list" ]; then
                    echo "Resetting $unit to the first server on the list"
                    manual_restart "$unit" reset
                fi
            done
            IFS=$oldIFS
        fi
    ;;
    "stop")
        crontab_entry delete
    ;;
    "restart")
        sh "$script_path" stop
        sh "$script_path" start
    ;;
    *)
        echo "Usage: $0 run|start|stop|restart|rotate|identify"
        exit 1
    ;;
esac
