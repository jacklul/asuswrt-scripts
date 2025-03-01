#!/bin/sh
# place this script in /jffs/scripts
# to emulate 'services-start' and also initial start of 'firewall-start' and 'nat-start'

case "$1" in
    "start")
        # emulate services-start
        [ -x "/jffs/scripts/services-start" ] && sh /jffs/scripts/services-start &

        wan_interface="$(nvram get wan0_ifname)"
        [ "$(nvram get wan0_gw_ifname)" != "$wan_interface" ] && wan_interface=$(nvram get wan0_gw_ifname)
        [ -n "$(nvram get wan0_pppoe_ifname)" ] && wan_interface="$(nvram get wan0_pppoe_ifname)"

        # emulate firewall-start and nat-start
        [ -x "/jffs/scripts/firewall-start" ] && sh /jffs/scripts/firewall-start "$wan_interface" &
        [ -x "/jffs/scripts/nat-start" ] && sh /jffs/scripts/nat-start "$wan_interface" &
    ;;
esac
