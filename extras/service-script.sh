#!/bin/sh
# $2 = event, $3 = target
# add this script to EXECUTE_COMMAND in service-event.conf
# to emulate firewall-start, nat-start, 
# service-event and service-event-end scripts

[ -z "$3" ] && exit

if [ ! -f "/usr/sbin/helper.sh" ]; then
    case "$3" in
        "firewall"|"vpnc_dev_policy"|"pms_device"|"ftpd"|"ftpd_force"|"aupnpc"|"chilli"|"CP"|"radiusd"|"webdav"|"enable_webdav"|"time"|"snmpd"|"vpnc"|"vpnd"|"pptpd"|"openvpnd"|"wgs"|"yadns"|"dnsfilter"|"tr"|"tor")
            WAN_INTERFACE="$(nvram get wan0_ifname)"
            [ "$(nvram get wan0_gw_ifname)" != "$WAN_INTERFACE" ] && WAN_INTERFACE=$(nvram get wan0_gw_ifname)
            [ -n "$(nvram get wan0_pppoe_ifname)" ] && WAN_INTERFACE="$(nvram get wan0_pppoe_ifname)"

            # emulate firewall-start and nat-start
            [ -x "/jffs/scripts/firewall-start" ] && /jffs/scripts/firewall-start "$WAN_INTERFACE" &
            [ -x "/jffs/scripts/nat-start" ] && /jffs/scripts/nat-start "$WAN_INTERFACE" &
        ;;
    esac

    # emulate service-event and service-event-end
    [ -x "/jffs/scripts/service-event" ] && /jffs/scripts/service-event "$2" "$3" &
    [ -x "/jffs/scripts/service-event-end" ] && /jffs/scripts/service-event-end "$2" "$3" &
fi
