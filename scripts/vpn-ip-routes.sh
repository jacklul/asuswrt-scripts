#!/bin/sh
# Made by Jack'lul <jacklul.github.io>
#
# Allow routing specific IPs through specified VPN Fusion profiles
#
# Inspired by Domain VPN Routing script:
#  https://github.com/Ranger802004/asusmerlin/tree/main/domain_vpn_routing
#
# fwmark based implementation based on mentioned above script
#

#jas-update=vpn-ip-routes.sh
#shellcheck disable=SC2155
#shellcheck source=./common.sh
readonly common_script="$(dirname "$0")/common.sh"
if [ -f "$common_script" ]; then . "$common_script"; else { echo "$common_script not found" >&2; exit 1; } fi

ROUTE_IPS="" # route IPs to specific VPNs, in format '5=1.1.1.1' (VPNC_ID=IP), separated by spaces, to find VPNC_ID run 'jas vpn-ip-routes identify'
ROUTE_IPS6="" # same as ROUTE_IPS but for IPv6, separated by spaces
EXECUTE_COMMAND="" # execute a command after rules are applied or removed (receives arguments: $1 = action - add/remove)
RUN_EVERY_MINUTE= # verify that the rules are still set (true/false), empty means false when service-event script is available but otherwise true
RETRY_ON_ERROR=false # retry setting the rules on error (once per run)

# The following is development/testing and might not work
USE_FWMARKS=false # use fwmarks instead of IP rules, this could improve routing performance with many rules
FWMARK_POOL="0xa000 0xb000 0xc000 0xd000 0xe000" # available fwmarks to use in rules, separated by spaces, careful as some can be in use by the firmware
FWMARK_MASK="0xf000" # fwmark mask to use, it must be compatible with all entries in FWMARK_POOL

load_script_config

state_file="$TMP_DIR/$script_name"
readonly CHAIN="jas-${script_name}"

is_vpnc_active() {
    get_vpnc_clientlist | awk -F '>' '{print $7, $6}' | grep -Fq "$1 1"
}

get_profile_desc() {
    _desc="$(get_vpnc_clientlist | awk -F '>' '{print $7, $1}' | grep "^$1" | awk '{sub(/^[^ ]* /, ""); print}')"
    [ -n "$_desc" ] && echo "$_desc" || echo "ID = $1"
}

get_fwmark_for_idx() {
    # Since we are using eval later, it's worth making sure $1 is just a number
    case $1 in
        ''|*[!0-9]*) echo "Expected numeric argument" >&2; return 1 ;;
        *) ;;
    esac

    _varname="_fwmark_$1"
    _value="$(eval "echo \$$_varname")"

    if [ -n "$_value" ]; then
        echo "$_value"
    else
        [ -z "$fwmark_pool" ] && fwmark_pool="$FWMARK_POOL"
        _first_fwmark=$(echo "$fwmark_pool" | cut -d ' ' -f 1)
        [ -z "$_first_fwmark" ] && return 1 # No more available fmarks
        fwmark_pool=$(echo "$fwmark_pool" | sed -E "s/$_first_fwmark//" | awk '{$1=$1};1')
        eval "$_varname=$_first_fwmark"
        echo "$_first_fwmark"
    fi
}

cleanup_ip_rules() {
    # inherited: _ip

    # Clean up any existing ip rules for inactive profiles
    for _idx in 5 6 7 8 9 10 11 12 13 14 15 16; do # VPNC_UNIT_BASIC - MAX_VPNC_PROFILE (max 12 profiles)
        if ! echo "$active_idx" | grep -Fq " $_idx "; then
            _priority=$((1000+_idx))

            if [ -n "$($_ip rule show priority "$_priority")" ]; then
                while $_ip rule del priority "$_priority" 2> /dev/null; do :; done

                rules_removed=1
                ! echo "$removed_idx" | grep -Fq " $_idx " && removed_idx="$removed_idx $_idx "
            fi
        fi
    done
}

iptables_rules() {
    _for_iptables="iptables"
    [ "$(nvram get ipv6_service)" != "disabled" ] && _for_iptables="$_for_iptables ip6tables"

    modprobe xt_comment

    for _iptables in $_for_iptables; do
        if [ "$_iptables" = "ip6tables" ]; then
            _route_ips="$ROUTE_IPS6"
            _ip="ip -6"
        else
            _route_ips="$ROUTE_IPS"
            _ip="ip -4"
        fi

        [ -z "$_route_ips" ] && continue

        case "$1" in
            "add")
                # firewall restart does not delete out chains in mangle table?
                if ! $_iptables -t mangle -nL "$CHAIN" > /dev/null 2>&1; then
                    $_iptables -t mangle -N "$CHAIN"
                fi

                for _chain in PREROUTING OUTPUT POSTROUTING; do
                    if ! $_iptables -t mangle -C "$_chain" -j "$CHAIN" -m comment --comment "jas-$script_name" > /dev/null 2>&1; then
                        $_iptables -t mangle -A "$_chain" -j "$CHAIN" -m comment --comment "jas-$script_name"
                    fi
                done

                #if ! $_iptables -t mangle -C PREROUTING -j CONNMARK --restore-mark > /dev/null 2>&1; then
                #    $_iptables -t mangle -I PREROUTING -j CONNMARK --restore-mark
                #fi

                #if ! $_iptables -t mangle -C POSTROUTING -j CONNMARK --save-mark > /dev/null 2>&1; then
                #    $_iptables -t mangle -A POSTROUTING -j CONNMARK --save-mark
                #fi

                # If the configuration has changed, flush the chain before setting new rules
                [ -n "$do_update" ] && $_iptables -t mangle -F "$CHAIN"

                for _route_ip in $_route_ips; do
                    _idx="$(echo "$_route_ip" | cut -d '=' -f 1)"

                    if is_vpnc_active "$_idx"; then
                        _ip_addr="$(echo "$_route_ip" | cut -d '=' -f 2)"
                        _fwmark="$(get_fwmark_for_idx "$_idx")"

                        if [ -z "$_fwmark" ]; then
                            if [ -z "$fwmark_exhausted_notify" ]; then
                                logecho "Error: Exhausted fwmark pool" error
                                fwmark_exhausted_notify=true
                            fi

                            continue;
                        fi

                        _priority=$((1000+_idx))

                        if [ -z "$($_ip rule show from all fwmark "$_fwmark/$FWMARK_MASK" table "$_idx" priority "$_priority")" ]; then
                            $_ip rule add from all fwmark "$_fwmark/$FWMARK_MASK" table "$_idx" priority "$_priority" || rules_error=1
                        fi

                        if ! $_iptables -t mangle -C "$CHAIN" -d "$_ip_addr" -j MARK --set-xmark "$_fwmark/$FWMARK_MASK" > /dev/null 2>&1; then
                            if $_iptables -t mangle -A "$CHAIN" -d "$_ip_addr" -j MARK --set-xmark "$_fwmark/$FWMARK_MASK"; then
                                rules_added=1
                                ! echo "$added_idx" | grep -Fq " $_idx " && added_idx="$added_idx $_idx "
                            else
                                rules_error=1
                            fi
                        fi

                        ! echo "$active_idx" | grep -Fq " $_idx " && active_idx="$active_idx $_idx "
                    fi
                done
            ;;
            "remove")
                remove_iptables_rules_by_comment "mangle"

                if $_iptables -t mangle -nL "$CHAIN" > /dev/null 2>&1; then
                    $_iptables -t mangle -F "$CHAIN"
                    $_iptables -t mangle -X "$CHAIN" || rules_error=1
                fi
            ;;
        esac

        cleanup_ip_rules
        $_ip route flush cache
    done

    [ "$rules_error" = 1 ] && logecho "Errors detected while modifying iptables or IP routing rules ($1)" error
    [ -z "$rules_error" ] && return 0 || return 1
}

ip_route_rules() {
    _for_ip="ip"
    [ "$(nvram get ipv6_service)" != "disabled" ] && _for_ip="$_for_ip ip6"

    for _ip in $_for_ip; do
        if [ "$_ip" = "ip6" ]; then
            _route_ips="$ROUTE_IPS6"
            _ip="ip -6"
        else
            _route_ips="$ROUTE_IPS"
            _ip="ip -4"
        fi

        case "$1" in
            "add")
                [ -z "$_route_ips" ] && continue

                for _route_ip in $_route_ips; do
                    _idx="$(echo "$_route_ip" | cut -d '=' -f 1)"

                    if is_vpnc_active "$_idx"; then
                        _ip_addr="$(echo "$_route_ip" | cut -d '=' -f 2)"
                        _priority=$((1000+_idx))

                        # If the configuration has changed, remove all rules of this idx before setting new rules
                        if [ -n "$do_update" ] && ! echo "$active_idx" | grep -Fq " $_idx "; then
                            while $_ip rule del priority "$_priority" 2> /dev/null; do :; done
                        fi

                        if [ -z "$($_ip rule show from all to "$_ip_addr" table "$_idx" priority "$_priority")" ]; then
                            if $_ip rule add from all to "$_ip_addr" table "$_idx" priority "$_priority"; then
                                rules_added=1
                                ! echo "$added_idx" | grep -Fq " $_idx " && added_idx="$added_idx $_idx "
                            else
                                rules_error=1
                            fi
                        fi

                        ! echo "$active_idx" | grep -Fq " $_idx " && active_idx="$active_idx $_idx "
                    fi
                done
            ;;
        esac

        cleanup_ip_rules
        $_ip route flush cache
    done

    [ "$rules_error" = 1 ] && logecho "Errors detected while modifying IP routing rules ($1)" error
    [ -z "$rules_error" ] && return 0 || return 1
}

rules() {
    { [ -z "$ROUTE_IPS" ] && [ -z "$ROUTE_IPS6" ] ; } && { logecho "Error: ROUTE_IPS/ROUTE_IPS6 is not set" error; exit 1; }

    lockfile lockwait

    # Compare with previous configuration
    if [ -f "$state_file" ]; then
        . "$state_file"

        [ "$ROUTE_IPS" != "$LAST_ROUTE_IPS" ] && do_update=1
        [ "$ROUTE_IPS6" != "$LAST_ROUTE_IPS6" ] && do_update=1

        if [ "$USE_FWMARKS" != "$LAST_USE_FWMARKS" ] || [ "$FWMARK_POOL" != "$LAST_FWMARK_POOL" ] || [ "$FWMARK_MASK" != "$LAST_FWMARK_MASK" ]; then
            echo "Error: Configuration for fwmarks has changed, please restart the script" >&2
            exit 1
        fi
    fi

    rules_added=
    rules_removed=
    added_idx=
    active_idx=

    if [ "$USE_FWMARKS" = true ]; then
        iptables_rules "$1"
    else
        ip_route_rules "$1"
    fi

    if [ "$rules_added" = 1 ]; then
        _added_profiles=
        for _idx in $added_idx; do
            _added_profiles="$_added_profiles '$(get_profile_desc "$_idx")'"
        done

        logecho "Added IP routing rules for VPN profiles: $(echo "$_added_profiles" | awk '{$1=$1};1')" alert
    fi

    if [ "$rules_removed" = 1 ]; then
        _removed_profiles=
        for _idx in $removed_idx; do
            _removed_profiles="$_removed_profiles '$(get_profile_desc "$_idx")'"
        done

        logecho "Removed IP routing rules for VPN profiles: $(echo "$_removed_profiles" | awk '{$1=$1};1')" alert
    fi

    cat <<EOT > "$state_file"
LAST_ROUTE_IPS="$ROUTE_IPS"
LAST_ROUTE_IPS6="$ROUTE_IPS6"
LAST_USE_FWMARKS="$USE_FWMARKS"
LAST_FWMARK_POOL="$FWMARK_POOL"
LAST_FWMARK_MASK="$FWMARK_MASK"
EOT

    [ -n "$EXECUTE_COMMAND" ] && { [ -n "$rules_added" ] || [ -n "$rules_removed" ] ; } && eval "$EXECUTE_COMMAND $1"

    lockfile unlock
    [ -z "$rules_error" ] && return 0 || return 1
}

case "$1" in
    "run")
        rules add || { [ "$RETRY_ON_ERROR" = true ] && rules add; }
    ;;
    "identify")
        printf "%-3s %-7s %-20s\n" "ID" "Active" "Description"
        printf "%-3s %-7s %-20s\n" "--" "------" "--------------------"

        IFS="$(printf '\n\b')"
        for entry in $(get_vpnc_clientlist); do
            desc="$(echo "$entry" | awk -F '>' '{print $1}')"
            active="$(echo "$entry" | awk -F '>' '{print $6}')"
            vpnc_idx="$(echo "$entry" | awk -F '>' '{print $7}')"
            [ "$active" = "1" ] && active=yes || active=no

            printf "%-3s %-7s %-50s\n" "$vpnc_idx" "$active" "$desc"
        done
    ;;
    "start")
        rules add

        # Set value of empty RUN_EVERY_MINUTE depending on situation
        execute_script_basename "service-event.sh" check && service_event_active=true
        [ -z "$RUN_EVERY_MINUTE" ] && [ -z "$service_event_active" ] && RUN_EVERY_MINUTE=true

        if [ "$RUN_EVERY_MINUTE" = true ]; then
            crontab_entry add "*/1 * * * * $script_path run"
        fi
    ;;
    "stop")
        crontab_entry delete
        rm -f "$state_file"
        rules remove
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
