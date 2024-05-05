#!/bin/sh
# place this script in /jffs/scripts
# to emulate services-start and also initial
# start of firewall-start and nat-start

case "$1" in
    "start")
        # emulate services-start
        [ -x "/jffs/scripts/services-start" ] && sh /jffs/scripts/services-start &

        WAN_INTERFACE="$(nvram get wan0_ifname)"
        [ "$(nvram get wan0_gw_ifname)" != "$WAN_INTERFACE" ] && WAN_INTERFACE=$(nvram get wan0_gw_ifname)
        [ -n "$(nvram get wan0_pppoe_ifname)" ] && WAN_INTERFACE="$(nvram get wan0_pppoe_ifname)"

        # emulate firewall-start and nat-start
        [ -x "/jffs/scripts/firewall-start" ] && sh /jffs/scripts/firewall-start "$WAN_INTERFACE" &
        [ -x "/jffs/scripts/nat-start" ] && sh /jffs/scripts/nat-start "$WAN_INTERFACE" &
    ;;
esac
