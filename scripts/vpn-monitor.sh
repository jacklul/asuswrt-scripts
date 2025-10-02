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
#shellcheck shell=ash
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

VPNC_IDS="" # select which VPN profiles to monitor, separated by spaces, empty means all, to find VPNC_ID run 'jas vpn-ip-routes identify'
TEST_PING="1.1.1.1" # IP address to ping, leave empty to skip this check
TEST_PING_LIMIT=300 # max ping time in ms, if ping is higher than this it marks ping test as failed, set to empty to disable
TEST_URL="https://ipecho.net/plain" # URL for fetch check, leave empty to skip this check
TEST_RETRIES=3 # number of retries for connectivity test, it is considered failed if all retries fail
RESTART_LIMIT=5 # limit number of restarts per unit, 0 means no limit, counter resets on successful connectivity check
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

    local _state_file="$state_file-$2.tmp"
    local _counter=0

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
    local _type _id _unit _file _nvram_addr _service

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
    else
        echo "Invalid interface: $1" >&2
        return 1
    fi

    local _reset=
    [ "$2" = "reset" ] && _reset=true

    local _is_active=
    if interface_exists "$1"; then
        _is_active=true
    fi

    if [ -f "$_file" ]; then
        local _total="$(cat "$_file" | grep -cv '^\(#\|\s*$\)')"

        if [ -z "$_total" ] || [ "$_total" -eq 0 ]; then
            return 1
        fi

        local _next

        if [ -z "$_reset" ]; then
            if [ "$ROTATE_RANDOM" = true ]; then
                local _rand=$(awk 'BEGIN {srand(); print int(32768 * rand())}')
                _next=$((_rand%_total+1))
            else
                local _current="$(nvram get "$_nvram_addr")"
                local _last=$(grep -v '^\(#\|\s*$\)' "$_file" | grep -n "$_current" | head -n 1 | cut -d: -f1)
                [ -z "$_last" ] && _last=0
                _next=$((_last+1))
                [ "$_next" -gt "$_total" ] && _next=1
            fi
        else
            _next=1
        fi

        local _line="$(grep -v '^\(#\|\s*$\)' "$_file" | sed -ne "${_next}p" -e 's/\r\n\|\n//g')"
        local _new_addr

        if [ "$_type" = "WireGuard" ]; then
            if [ "$(echo "$_line" | grep -o ',' | wc -l)" -lt 4 ]; then
                echo "Invalid line in $_file: $_line" >&2
                return 1
            fi

            local _cur_ep_addr="$(nvram get "wgc${_id}_ep_addr")"

            # This is NOT compatible with lists created for VPNMON
            local _new_ep_addr="$(echo "$_line" | cut -d ',' -f 1)"
            local _new_ep_port="$(echo "$_line" | cut -d ',' -f 2)"
            local _new_addr="$(echo "$_line" | cut -d ',' -f 3)"
            local _new_priv="$(echo "$_line" | cut -d ',' -f 4)"
            local _new_ppub="$(echo "$_line" | cut -d ',' -f 5)"
            local _new_psk="$(echo "$_line" | cut -d ',' -f 6)"

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
            local _cur_addr="$(nvram get "vpn_client${_id}_addr")"

            # This is compatible with lists created for VPNMON
            local _new_addr="$(echo "$_line" | cut -d ',' -f 1)"
            local _new_port="$(echo "$_line" | cut -d ',' -f 2)"

            [ "$_cur_addr" = "$_new_addr" ] && return 0 # no change
            [ "$_new_addr" = "$_new_port" ] && _new_port= # if port is same as address it means port was not provided

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
                [ -n "$EXECUTE_COMMAND" ] && eval "$EXECUTE_COMMAND $_unit $_new_addr"

                logecho "Restarted $_type client $_id ($reason) with new server address: $_new_addr" alert
            else
                logecho "Set new server address for $_type client $_id: $_new_addr" alert
            fi
        else
            logecho "Error: Failed to set new server address for $_type client $_id" error
        fi
    elif interface_exists "$1"; then
        service "restart_${_service}" >/dev/null 2>&1
        [ -n "$EXECUTE_COMMAND" ] && eval "$EXECUTE_COMMAND $_unit"

        logecho "Restarted $_type client $_id ($reason)" alert
    fi
}

check_connection_by_ifname() {
    local _retries="$TEST_RETRIES"
    local _addr

    if [ -n "$2" ]; then
        _addr="$(ip addr show "$1" | awk '/inet / {print $2}')"
        [ -n "$_addr" ] && ip rule add from "$_addr" lookup "$2" prio 55 > /dev/null 2>&1
    fi

    local _success _ping_success _url_success _ping

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

    [ -n "$_addr" ] && ip rule del prio 55 > /dev/null 2>&1
    [ -n "$_success" ] && return 0
    return 1;
}

check_connections() {
    { [ -z "$TEST_PING" ] && [ -z "$TEST_URL" ] ; } && { logecho "Error: TEST_PING/TEST_URL is not set" error; exit 1; }
    { [ "$(nvram get wan0_state_t)" != "2" ] && [ "$(nvram get wan1_state_t)" != "2" ] ; } && { echo "WAN network is not connected" >&2; return 1; }

    local _vpnc_profiles="$(get_vpnc_clientlist | awk -F '>' '{print $6, $2, $3, $7}' | grep "^1" | cut -d ' ' -f 2-)"

    local _entry _type _id _idx _unit _iface _counter

    local _oldIFS=$IFS
    IFS="$(printf '\n\b')"
    for _entry in $_vpnc_profiles; do
        _type="$(echo "$_entry" | cut -d ' ' -f 1)"
        _id="$(echo "$_entry" | cut -d ' ' -f 2)"
        _idx="$(echo "$_entry" | cut -d ' ' -f 3)"

        [ -n "$VPNC_IDS" ] && ! echo " $VPNC_IDS " | grep -Fq " $_idx " && continue

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
            echo "$_unit connection is DOWN"

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

    local _id _if

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
        printf "%-3s %-7s %-7s %-22s %-20s\n" "ID" "Unit" "Active" "Server address" "Description"
        printf "%-3s %-7s %-7s %-22s %-20s\n" "--" "------" "------" "---------------------" "--------------------"

        IFS="$(printf '\n\b')"
        for entry in $(get_vpnc_clientlist); do
            desc="$(echo "$entry" | awk -F '>' '{print $1}')"
            type="$(echo "$entry" | awk -F '>' '{print $2}')"
            id="$(echo "$entry" | awk -F '>' '{print $3}')"
            idx="$(echo "$entry" | awk -F '>' '{print $7}')"
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

            printf "%-3s %-7s %-7s %-22s %-50s\n" "$idx" "$unit" "$active" "$address" "$desc"
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
                    restart_counter reset "$_unit"
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
