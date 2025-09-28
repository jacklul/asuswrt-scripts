#!/bin/sh
# Made by Jack'lul <jacklul.github.io>
#
# Allow VPN clients to utilize virtual server/port forwarding rules
#

#jas-update=vpn-vserver.sh
#shellcheck disable=SC2155
#shellcheck source=./common.sh
readonly common_script="$(dirname "$0")/common.sh"
if [ -f "$common_script" ]; then . "$common_script"; else { echo "$common_script not found" >&2; exit 1; } fi

VPN_ADDRESSES="" # VPN addresses (IPv4) to affect, in format '10.10.10.10', separated by spaces, empty means auto detect, to find VPN addresses run 'jas vpn-vserver identify'
VPN_ADDRESSES6="" # same as VPN_ADDRESSES but for IPv6, separated by spaces, no auto detect available
VPN_EXCLUSIVE=false # limit virtual server rules to VPN addresses only, this removes firmware made rules for WAN addresses
EXECUTE_COMMAND="" # execute a command after firewall rules are applied or removed (receives arguments: $1 = action - add/remove)
RUN_EVERY_MINUTE= # verify that the rules are still set (true/false), empty means false when service-event script is available but otherwise true
RETRY_ON_ERROR=false # retry setting the rules on error (once per run)

load_script_config

state_file="$TMP_DIR/$script_name"

get_interface_address() {
    ip addr show "$1" | grep inet | awk '{print $2}' | cut -d '/' -f 1
}

firewall_rules() {
    if { [ -z "$VPN_ADDRESSES" ] && [ -z "$VPN_ADDRESSES6" ] ; }; then
        _vpnc_profiles="$(get_vpnc_clientlist | awk -F '>' '{print $6, $2, $3}' | grep "^1" | cut -d ' ' -f 2-)"

        _oldIFS=$IFS
        IFS="$(printf '\n\b')"
        for _entry in $_vpnc_profiles; do
            _type="$(echo "$_entry" | cut -d ' ' -f 1)"
            _id="$(echo "$_entry" | cut -d ' ' -f 2)"

            if [ "$_type" = "OpenVPN" ]; then
                if [ "$(nvram get "vpn_client${_id}_state")" = "2" ]; then
                    _ifname="$(nvram get "vpn_client${_id}_if")"
                    _address="$(get_interface_address "${_ifname}1${_id}")"

                    if [ -n "$_address" ]; then
                        VPN_ADDRESSES="$VPN_ADDRESSES $_address"
                    fi
                fi
            elif [ "$_type" = "WireGuard" ]; then
                if [ "$(nvram get "wgc${_id}_enable")" = "1" ]; then
                    _address="$(get_interface_address "wgc${_id}")"

                    if [ -n "$_address" ]; then
                        VPN_ADDRESSES="$VPN_ADDRESSES $_address"
                    fi
                fi
            fi
        done
        IFS=$_oldIFS

        { [ -z "$VPN_ADDRESSES" ] && [ -z "$VPN_ADDRESSES6" ] ; } && return # silently exit
    fi

    lockfile lockwait

    _for_iptables="iptables"
    [ "$(nvram get ipv6_service)" != "disabled" ] && _for_iptables="$_for_iptables ip6tables"

    modprobe xt_comment

    _rules_action=
    _rules_error=
    for _iptables in $_for_iptables; do
        if [ "$_iptables" = "ip6tables" ]; then
            _vpn_addresses="$VPN_ADDRESSES6"
            _state_file="$state_file.ipv6"
        else
            _vpn_addresses="$VPN_ADDRESSES"
            _state_file="$state_file"
        fi

        [ -z "$_vpn_addresses" ] && continue

        case "$1" in
            "add")
                _vserver_start="$($_iptables -t nat -nvL PREROUTING --line-numbers | grep -E "VSERVER .* all" | tail -1 | awk '{print $1}')"
                [ -z "$_vserver_start" ] && _vserver_start=0

                for _vpn_address in $_vpn_addresses; do
                    if
                        ! $_iptables -t nat -C PREROUTING -d "$_vpn_address" -j VSERVER \
                            -m comment --comment "jas-$script_name" > /dev/null 2>&1
                    then
                        _vserver_start=$((_vserver_start+1))

                        $_iptables -t nat -I PREROUTING "$_vserver_start" -d "$_vpn_address" -j VSERVER \
                            -m comment --comment "jas-$script_name" \
                                && _rules_action=1 || _rules_error=1
                    fi
                done

                if [ "$VPN_EXCLUSIVE" = true ]; then
                    _firmware_rules="$($_iptables -t nat -S | grep -F "j VSERVER" | grep -Fv "jas-$script_name")"

                    if [ -n "$_firmware_rules" ]; then
                        echo "$_firmware_rules" > "$_state_file"

                        # Delete the rules made by the firmware
                        echo "$_firmware_rules" | sed "s/^-A/$_iptables -t nat -D/" | while read -r _cmd; do
                            eval "$_cmd"
                        done
                    fi
                fi
            ;;
            "remove")
                remove_iptables_rules_by_comment "nat" && _rules_action=-1

                if [ -f "$_state_file" ]; then
                    _firmware_rules="$(cat "$_state_file")"
                    rm -f "$_state_file"

                    if [ -n "$_firmware_rules" ]; then
                        # Reverse the order of rules when adding them back to reflect how they were originally
                        echo "$_firmware_rules" | sed -n -e "s/^-A/$_iptables -t nat -I/" -e '1!G;h;$p' | while read -r _cmd; do
                            eval "$_cmd"
                        done
                    fi
                fi
            ;;
        esac
    done

    [ "$_rules_error" = 1 ] && logecho "Errors detected while modifying firewall rules ($1)" error

    if [ -n "$_rules_action" ]; then
        if [ "$_rules_action" = 1 ]; then
            logecho "Enabled virtual server rules for VPN addresses: $(echo "$VPN_ADDRESSES $VPN_ADDRESSES6" | awk '{$1=$1};1')" logger
        else
            logecho "Disabled virtual server rules for VPN addresses: $(echo "$VPN_ADDRESSES $VPN_ADDRESSES6" | awk '{$1=$1};1')" logger
        fi
    fi

    [ -n "$EXECUTE_COMMAND" ] && [ -n "$_rules_action" ] && $EXECUTE_COMMAND "$1"

    lockfile unlock
    [ -z "$_rules_error" ] && return 0 || return 1
}

case "$1" in
    "run")
        firewall_rules add || { [ "$RETRY_ON_ERROR" = true ] && firewall_rules add; }
    ;;
    "identify")
        printf "%-16s %-7s %-20s\n" "Address" "Active" "Description"
        printf "%-16s %-7s %-20s\n" "---------------" "------" "--------------------"

        IFS="$(printf '\n\b')"
        for entry in $(get_vpnc_clientlist); do
            desc="$(echo "$entry" | awk -F '>' '{print $1}')"
            type="$(echo "$entry" | awk -F '>' '{print $2}')"
            id="$(echo "$entry" | awk -F '>' '{print $3}')"
            active="$(echo "$entry" | awk -F '>' '{print $6}')"
            [ "$active" = "1" ] && active=yes || active=no
            address=

            if [ "$type" = "OpenVPN" ]; then
                if [ "$(nvram get "vpn_client${id}_state")" = "2" ]; then
                    ifname="$(nvram get "vpn_client${id}_if")"
                    address="$(get_interface_address "${ifname}1${id}")"

                fi
            elif [ "$type" = "WireGuard" ]; then
                if [ "$(nvram get "wgc${id}_enable")" = "1" ]; then
                    address="$(get_interface_address "wgc${id}")"
                fi
            else
                continue
            fi

            [ -z "$address" ] && address="N/A"

            printf "%-16s %-7s %-50s\n" "$address" "$active" "$desc"
        done
    ;;
    "start")
        firewall_rules add

        # Set value of empty RUN_EVERY_MINUTE depending on situation
        execute_script_basename "service-event.sh" check && service_event_active=true
        [ -z "$RUN_EVERY_MINUTE" ] && [ -z "$service_event_active" ] && RUN_EVERY_MINUTE=true

        if [ "$RUN_EVERY_MINUTE" = true ]; then
            crontab_entry add "*/1 * * * * $script_path run"
        fi
    ;;
    "stop")
        crontab_entry delete
        firewall_rules remove
    ;;
    "restart")
        sh "$script_path" stop
        sh "$script_path" start
    ;;
    *)
        echo "Usage: $0 run|start|stop|restart|identify"
        exit 1
    ;;
esac
