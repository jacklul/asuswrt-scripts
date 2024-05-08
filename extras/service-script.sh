#!/bin/sh
# $1 = event, $2 = target
# add this script to EXECUTE_COMMAND in service-event.conf
# to emulate firewall-start, nat-start,
# service-event and service-event-end scripts

[ -z "$2" ] && exit
[ -f "/usr/sbin/helper.sh" ] && exit # Don't run on Asuswrt-Merlin

case "$1" in
    "start"|"restart")
        case "$2" in
            "firewall"|"vpnc_dev_policy"|"pms_device"|"ftpd"|"ftpd_force"|"aupnpc"|"chilli"|"CP"|"radiusd"|"webdav"|"enable_webdav"|"time"|"snmpd"|"vpnc"|"vpnd"|"pptpd"|"openvpnd"|"wgs"|"yadns"|"dnsfilter"|"tr"|"tor")
                WAN_INTERFACE="$(nvram get wan0_ifname)"
                [ "$(nvram get wan0_gw_ifname)" != "$WAN_INTERFACE" ] && WAN_INTERFACE=$(nvram get wan0_gw_ifname)
                [ -n "$(nvram get wan0_pppoe_ifname)" ] && WAN_INTERFACE="$(nvram get wan0_pppoe_ifname)"

                # emulate firewall-start and nat-start
                [ -x "/jffs/scripts/firewall-start" ] && sh /jffs/scripts/firewall-start "$WAN_INTERFACE" &
                [ -x "/jffs/scripts/nat-start" ] && sh /jffs/scripts/nat-start "$WAN_INTERFACE" &
            ;;
        esac
    ;;
esac

# emulate service-event and service-event-end
[ -x "/jffs/scripts/service-event" ] && sh /jffs/scripts/service-event "$1" "$2" &
[ -x "/jffs/scripts/service-event-end" ] && sh /jffs/scripts/service-event-end "$1" "$2" &