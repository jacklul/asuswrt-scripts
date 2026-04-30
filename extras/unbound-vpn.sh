#!/bin/sh
# This script will set up a dummy network interface and an IP routing rule
# to route DNS queries from Unbound through a specific VPN connection.
#
# Add to unbound.conf: "outgoing-interface: 172.16.254.1"
#

# can be changed at any time - re-running the script will apply new changes
vpn_idx="5"

# these should not be changed after running
if_name=unbound
if_addr=172.16.254.1
rule_prio=999

##################################################

tag="$(basename "$0")"
[ -t 0 ] && interactive=true

log_or_echo() {
    if [ -n "$interactive" ]; then
        echo "$1"
    else
        logger -t "$tag" "$1"
    fi
}

if ! ip link show "$if_name" > /dev/null 2>&1; then
    ip link add name "$if_name" type dummy
    ip link set "$if_name" up
    log_or_echo "Added dummy interface '$if_name'"
fi

if ! ip addr show dev "$if_name" | grep -Fq "$if_addr"; then
    ip addr add "$if_addr/24" brd + dev "$if_name"
    log_or_echo "Added address '$if_addr' to interface '$if_name'"
fi

ip addr show "$if_name"

vpnc_clientlist="$(nvram get vpnc_clientlist | tr '<' '\n' | awk -F '>' '{print $7, $6}')"
for idx in $vpn_idx; do
    active="$(echo "$vpnc_clientlist" | grep "^$idx 1")"
    [ -n "$active" ] && break
done
[ -n "$active" ] && vpn_idx="$idx" || vpn_idx=

exists="$(ip rule show priority "$rule_prio" 2> /dev/null)"

if
    [ -n "$exists" ] &&
    {
        { [ -n "$vpn_idx" ] && ! echo "$exists" | grep -Fq "lookup $vpn_idx" ; } || \
        ! echo "$exists" | grep -Fq "from $if_addr"
    }
then # rule exists but for a different table/address
    ip rule del priority "$rule_prio" 2> /dev/null
    exists=
fi

if [ -n "$active" ] && [ -z "$exists" ]; then
    ip rule add from "$if_addr" to all table "$vpn_idx" priority "$rule_prio"
    ip route flush cache
    log_or_echo "Added IP routing rule for VPN idx $vpn_idx"
elif [ -z "$active" ] && [ -n "$exists" ]; then
    ip rule del priority "$rule_prio"
    ip route flush cache
    log_or_echo "Removed IP routing rule"
fi

ip rule show priority "$rule_prio" 2> /dev/null

[ "$1" = "test" ] && dig TXT +short o-o.myaddr."$(awk 'BEGIN { srand(); print int(1 + rand() * (1000 - 1 + 1)) }')".google.com. @127.0.0.1 -p 5335
