#!/bin/sh
# Made by Jack'lul <jacklul.github.io>
#
# Allow routing specific IPs through specified VPN Fusion profiles
#

#jas-update=vpn-ip-routes.sh
#shellcheck disable=SC2155
#shellcheck source=./common.sh
readonly common_script="$(dirname "$0")/common.sh"
if [ -f "$common_script" ]; then . "$common_script"; else { echo "$common_script not found"; exit 1; } fi

ROUTE_IPS="" # route IPs to specific VPNs, in format '5=1.1.1.1' (VPN_ID=IP), separated by spaces, run script with 'profiles' argument to identify VPN profile IDs
ROUTE_IPS6="" # same as ROUTE_IPS but for IPv6, separated by spaces
STATE_FILE="$TMP_DIR/$script_name" # file to store last contents of the ROUTE_IPS and ROUTE_IPS6 variables
EXECUTE_COMMAND="" # execute a command after rules are applied or removed (receives arguments: $1 = action - add/remove)
RUN_EVERY_MINUTE= # verify that the rules are still set (true/false), empty means false when service-event script is available but otherwise true

load_script_config

for_ip="ip"
[ "$(nvram get ipv6_service)" != "disabled" ] && for_ip="$for_ip ip6"

load_vpnc_clientlist() {
    vpnc_clientlist="$(nvram get vpnc_clientlist | tr '<' '\n')"
}

is_vpnc_active() {
    [ -z "$vpnc_clientlist" ] && load_vpnc_clientlist
    echo "$vpnc_clientlist" | awk -F '>' '{print $7, $6}' | grep -Fq "$1 1"
}

get_profile_desc() {
    [ -z "$vpnc_clientlist" ] && load_vpnc_clientlist
    _desc="$(echo "$vpnc_clientlist" | awk -F '>' '{print $7, $1}' | grep "^$1" | awk '{sub(/^[^ ]* /, ""); print}')"
    [ -n "$_desc" ] && echo "$_desc" || echo "ID = $1"
}

# @TODO Replace ip rules with fwmarks+iptables for better performance?
ip_route_rules() {
    { [ -z "$ROUTE_IPS" ] && [ -z "$ROUTE_IPS6" ] ; } && { logecho "Error: IPs to route are not set"; exit 1; }

    lockfile lockwait

    # Compare with previous configuration
    if [ -f "$STATE_FILE" ]; then
        . "$STATE_FILE"

        [ "$ROUTE_IPS" != "$LAST_ROUTE_IPS" ] && _update=1
        [ "$ROUTE_IPS6" != "$LAST_ROUTE_IPS6" ] && _update=1
    fi

    for _ip in $for_ip; do
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

                        # If the configuration has changed perform full cleanup before setting new rules
                        if [ -n "$_update" ] && ! echo "$_active_idx" | grep -Fq " $_idx "; then
                            while $_ip rule del priority "$_priority" 2> /dev/null; do :; done
                        fi

                        if [ -z "$($_ip rule show from all to "$_ip_addr" table "$_idx" priority "$_priority")" ]; then
                            if $_ip rule add from all to "$_ip_addr" table "$_idx" priority "$_priority"; then
                                _rules_added=1
                                ! echo "$_added_idx" | grep -Fq " $_idx " && _added_idx="$_added_idx $_idx "
                            else
                                _rules_error=1
                            fi
                        fi

                        ! echo "$_active_idx" | grep -Fq " $_idx " && _active_idx="$_active_idx $_idx "
                    fi
                done
            ;;
        esac

        # Clean up any existing rules for inactive profiles
        for _idx in 5 6 7 8 9 10 11 12 13 14 15 16; do # VPNC_UNIT_BASIC - MAX_VPNC_PROFILE (max 12 profiles)
            if ! echo "$_active_idx" | grep -Fq " $_idx "; then
                _priority=$((1000+_idx))

                if [ -n "$($_ip rule show priority "$_priority")" ]; then
                    while $_ip rule del priority "$_priority" 2> /dev/null; do :; done

                    _rules_removed=1
                    ! echo "$_removed_idx" | grep -Fq " $_idx " && _removed_idx="$_removed_idx $_idx "
                fi
            fi
        done
    done

    [ "$_rules_error" = 1 ] && logecho "Errors detected while modifying IP routing rules ($1)"

    if [ "$_rules_added" = 1 ]; then
        _added_profiles=
        for _idx in $_added_idx; do
            _added_profiles="$_added_profiles '$(get_profile_desc "$_idx")'"
        done

        logecho "Added IP routing rules for VPN profiles: $(echo "$_added_profiles" | awk '{$1=$1};1')" true
    fi

    if [ "$_rules_removed" = 1 ]; then
        _removed_profiles=
        for _idx in $_removed_idx; do
            _removed_profiles="$_removed_profiles '$(get_profile_desc "$_idx")'"
        done

        logecho "Removed IP routing rules for VPN profiles: $(echo "$_removed_profiles" | awk '{$1=$1};1')" true
    fi

    cat <<EOT > "$STATE_FILE"
LAST_ROUTE_IPS="$ROUTE_IPS"
LAST_ROUTE_IPS6="$ROUTE_IPS6"
EOT

    [ -n "$EXECUTE_COMMAND" ] && { [ -n "$_rules_added" ] || [ -n "$_rules_removed" ] ; } && $EXECUTE_COMMAND "$1"

    lockfile unlock
}

case "$1" in
    "run")
        ip_route_rules add
    ;;
    "profiles")
        load_vpnc_clientlist

        printf "%-3s %-7s %-20s\n" "ID" "Active" "Description"
        printf "%-3s %-7s %-20s\n" "--" "------" "--------------------"

        IFS="$(printf '\n\b')"
        for entry in $vpnc_clientlist; do
            desc="$(echo "$entry" | awk -F '>' '{print $1}')"
            active="$(echo "$entry" | awk -F '>' '{print $6}')"
            vpnc_idx="$(echo "$entry" | awk -F '>' '{print $7}')"
            [ "$active" = "1" ] && active=yes || active=no

            printf "%-3s %-7s %-50s\n" "$vpnc_idx" "$active" "$desc"
        done
    ;;
    "start")
        ip_route_rules add

        # Set value of empty RUN_EVERY_MINUTE depending on situation
        execute_script_basename "service-event.sh" check && service_event_active=true
        [ -z "$RUN_EVERY_MINUTE" ] && [ -z "$service_event_active" ] && RUN_EVERY_MINUTE=true

        if [ "$RUN_EVERY_MINUTE" = true ]; then
            crontab_entry add "*/1 * * * * $script_path run"
        fi
    ;;
    "stop")
        crontab_entry delete
        ip_route_rules remove
        rm -f "$STATE_FILE"
    ;;
    "restart")
        sh "$script_path" stop
        sh "$script_path" start
    ;;
    *)
        echo "Usage: $0 run|start|stop|restart|profiles"
        exit 1
    ;;
esac
