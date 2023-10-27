#!/bin/sh
# Made by Jack'lul <jacklul.github.io>
#
# Execute commands when specific service events occurs
#
# Implements basic service-event script handler from AsusWRT-Merlin:
#  https://github.com/RMerl/asuswrt-merlin.ng/wiki/User-scripts
#
# There is no blocking so there is no guarantee that this script will run before the event happens.
# You will probably want add extra code if you want to run code after the event happens.
# Scripts from this repository are already handled by the build-in script.
#

#shellcheck disable=SC2155

readonly SCRIPT_PATH="$(readlink -f "$0")"
readonly SCRIPT_NAME="$(basename "$SCRIPT_PATH" .sh)"
readonly SCRIPT_DIR="$(dirname "$SCRIPT_PATH")"
readonly SCRIPT_CONFIG="$SCRIPT_DIR/$SCRIPT_NAME.conf"
readonly SCRIPT_TAG="$(basename "$SCRIPT_PATH")"

SYSLOG_FILE="/tmp/syslog.log" # target syslog file to read
CACHE_FILE="/tmp/last_syslog_line" # where to store last parsed log line in case of crash
EXECUTE_COMMAND="" # command to execute in addition to build-in script (receives arguments: $1 = event, $2 = target)
SLEEP=1 # how to long to wait between each iteration

# Chain names definitions, must be changed if they were modified in their scripts
CHAINS_FORCEDNS="FORCEDNS"
CHAINS_SAMBA_MASQUERADE="SAMBA_MASQUERADE"
CHAINS_VPN_KILLSWITCH="VPN_KILLSWITCH"
CHAINS_WGS_LANONLY="WGS_LANONLY"
CHAINS_TAILSCALE="TAILSCALE"

if [ -f "$SCRIPT_CONFIG" ]; then
    #shellcheck disable=SC1090
    . "$SCRIPT_CONFIG"
fi

#shellcheck disable=SC2009
PROCESS_PID="$(ps w | grep "$SCRIPT_NAME.sh run" | grep -v "grep\|$$" | awk '{print $1}')"
PROCESS_PID_LIST="$(echo "$PROCESS_PID" | tr '\n' ' ' | awk '{$1=$1};1')"

case "$1" in
    "run")
        [ -f "/usr/sbin/helper.sh" ] && exit
        [ -n "$PROCESS_PID" ] && [ "$(echo "$PROCESS_PID" | wc -l)" -ge 2 ] && { echo "Already running!"; exit 1; }
        [ ! -f "$SYSLOG_FILE" ] && { logger -st "$SCRIPT_TAG" "Syslog log file does not exist: $SYSLOG_FILE"; exit 1; }

        set -e

        logger -st "$SCRIPT_TAG" "Started service event monitoring..."

        if [ -f "$CACHE_FILE" ]; then
            LAST_LINE="$(cat "$CACHE_FILE")"
        else
            LAST_LINE="$(wc -l < "$SYSLOG_FILE")"
            LAST_LINE="$((LAST_LINE+1))"
        fi

        while true; do
            TOTAL_LINES="$(wc -l < "$SYSLOG_FILE")"
            if [ "$TOTAL_LINES" -lt "$((LAST_LINE-1))" ]; then
                logger -st "$SCRIPT_TAG" "Log file has been rotated, resetting line pointer..."
                LAST_LINE=1
                continue
            fi

            NEW_LINES="$(tail "$SYSLOG_FILE" -n "+$LAST_LINE")"

            if [ -n "$NEW_LINES" ]; then
                MATCHING_LINES="$(echo "$NEW_LINES" | grep -En 'rc_service.*notify_rc' || echo '')"

                if [ -n "$MATCHING_LINES" ]; then
                    LAST_LINE_OLD=$LAST_LINE

                    IFS="$(printf '\n\b')"
                    for NEW_LINE in $MATCHING_LINES; do
                        LINE_NUMBER="$(echo "$NEW_LINE" | cut -f1 -d:)"
                        LAST_LINE="$((LAST_LINE_OLD+LINE_NUMBER))"

                        EVENTS="$(echo "$NEW_LINE" | awk -F 'notify_rc ' '{print $2}')"

                        if [ -n "$INIT" ]; then
                            OLDIFS=$IFS
                            IFS=';'
                            for EVENT in $EVENTS; do
                                if [ -n "$EVENT" ]; then
                                    EVENT_ACTION="$(echo "$EVENT" | cut -d'_' -f1)"
                                    EVENT_TARGET="$(echo "$EVENT" | cut -d'_' -f2- | cut -d' ' -f1)"

                                    logger -st "$SCRIPT_TAG" "Running script (args: \"${EVENT_ACTION}\" \"${EVENT_TARGET}\")"

                                    sh "$SCRIPT_PATH" event "$EVENT_ACTION" "$EVENT_TARGET" &
                                    [ -n "$EXECUTE_COMMAND" ] && "$EXECUTE_COMMAND" "$EVENT_ACTION" "$EVENT_TARGET" &
                                fi
                            done
                            IFS=$OLDIFS
                        fi
                    done
                else
                    TOTAL_LINES="$(echo "$NEW_LINES" | wc -l)"
                    LAST_LINE="$((LAST_LINE+TOTAL_LINES))"
                fi
            fi

            echo "$LAST_LINE" > "$CACHE_FILE"

            [ -z "$INIT" ] && INIT=1

            sleep "$SLEEP"
        done
    ;;
    "event")
        # $2 = event, $3 = target
        case "$3" in
            "firewall"|"vpnc_dev_policy"|"pms_device"|"ftpd"|"ftpd_force"|"aupnpc"|"chilli"|"CP"|"radiusd"|"webdav"|"enable_webdav"|"time"|"snmpd"|"vpnc"|"vpnd"|"pptpd"|"openvpnd"|"wgs"|"yadns"|"dnsfilter"|"tr"|"tor")
                if
                    [ -x "/jffs/scripts/vpn-killswitch.sh" ] ||
                    [ -x "/jffs/scripts/wgs-lanonly.sh" ] ||
                    [ -x "/jffs/scripts/force-dns.sh" ] ||
                    [ -x "/jffs/scripts/samba-masquerade.sh" ] ||
                    [ -x "/jffs/scripts/tailscale.sh" ]
                then
                    if [ "$4" != "merlin" ]; then # do not perform sleep-checks on Merlin firmware
                        _TIMER=0; while { # wait till our chains disappear
                            iptables -nL "$CHAINS_VPN_KILLSWITCH" >/dev/null 2>&1 ||
                            iptables -nL "$CHAINS_WGS_LANONLY" >/dev/null 2>&1 ||
                            iptables -nL "$CHAINS_FORCEDNS" -t nat >/dev/null 2>&1 ||
                            iptables -nL "$CHAINS_SAMBA_MASQUERADE" -t nat >/dev/null 2>&1 ||
                            iptables -nL "$CHAINS_TAILSCALE" >/dev/null 2>&1; 
                        } && [ "$_TIMER" -lt "60" ]; do
                            _TIMER=$((_TIMER+1))
                            sleep 1
                        done
                    fi

                    [ -x "/jffs/scripts/vpn-killswitch.sh" ] && /jffs/scripts/vpn-killswitch.sh run &
                    [ -x "/jffs/scripts/wgs-lanonly.sh" ] && /jffs/scripts/wgs-lanonly.sh run &
                    [ -x "/jffs/scripts/force-dns.sh" ] && /jffs/scripts/force-dns.sh run &
                    [ -x "/jffs/scripts/samba-masquerade.sh" ] && /jffs/scripts/samba-masquerade.sh run &
                    [ -x "/jffs/scripts/tailscale.sh" ] && /jffs/scripts/tailscale.sh firewall &

                fi
            ;;
            "allnet"|"net_and_phy"|"net"|"multipath"|"subnet"|"wan"|"wan_if"|"dslwan_if"|"dslwan_qis"|"dsl_wireless"|"wan_line"|"wan6"|"wan_connect"|"wan_disconnect"|"isp_meter")
                if
                    [ -x "/jffs/scripts/usb-network.sh" ] ||
                    [ -x "/jffs/scripts/dynamic-dns.sh" ]
                then
                    if [ "$4" != "merlin" ]; then # do not perform sleep-checks on Merlin firmware
                        _TIMER=0; while { # wait until wan goes down
                            { [ "$(nvram get wan0_state_t)" = "2" ] || [ "$(nvram get wan0_state_t)" = "0" ] || [ "$(nvram get wan0_state_t)" = "5" ]; } &&
                            { [ "$(nvram get wan1_state_t)" = "2" ] || [ "$(nvram get wan1_state_t)" = "0" ] || [ "$(nvram get wan1_state_t)" = "5" ]; };
                        } && [ "$_TIMER" -lt "10" ]; do
                            _TIMER=$((_TIMER+1))
                            sleep 1
                        done

                        _TIMER=0; while { # wait until wan goes up
                            [ "$(nvram get wan0_state_t)" != "2" ] &&
                            [ "$(nvram get wan1_state_t)" != "2" ];
                        } && [ "$_TIMER" -lt "60" ]; do
                            _TIMER=$((_TIMER+1))
                            sleep 1
                        done
                    fi

                    [ -x "/jffs/scripts/usb-network.sh" ] && /jffs/scripts/usb-network.sh run &
                    [ -x "/jffs/scripts/dynamic-dns.sh" ] && /jffs/scripts/dynamic-dns.sh run &
                fi

                # most of these also restart firewall so execute that too just in case
                sh "$SCRIPT_PATH" event restart firewall
            ;;
            "wireless")
                # this service event recreates rc_features so we have to re-run this script
                [ -x "/jffs/scripts/modify-features.sh" ] && /jffs/scripts/modify-features.sh run &
            ;;
            "usb_idle")
                # re-run in case script exited due to USB idle being set and now it has been disabled
                [ -x "/jffs/scripts/swap.sh" ] && /jffs/scripts/swap.sh run &
            ;;
        esac

        # these do not follow the naming scheme ("ACTION_SERVICE")
        case "${2}_${3}" in
            "ipsec_set"|"ipsec_start"|"ipsec_restart")
                sh "$SCRIPT_PATH" event restart firewall
            ;;
        esac

        exit
    ;;
    "init-run")
        [ -f "/usr/sbin/helper.sh" ] && exit

        if [ "$2" = "restart" ]; then
            kill "$PROCESS_PID_LIST"
            PROCESS_PID=
            sh "$SCRIPT_PATH" start
        fi

        [ -z "$PROCESS_PID" ] && nohup "$SCRIPT_PATH" run >/dev/null 2>&1 &
    ;;
    "start")
        if [ -f "/usr/sbin/helper.sh" ]; then # use service-event-end on Merlin firmware
            if [ ! -f /jffs/scripts/service-event-end ]; then
                cat <<EOT > /jffs/scripts/service-event-end
#!/bin/sh

EOT
                chmod 0755 /jffs/scripts/service-event-end
            fi

            if ! grep -q "$SCRIPT_PATH" /jffs/scripts/service-event-end; then
                echo "$SCRIPT_PATH event \"\$1\" \"\$2\" merlin &" >> /jffs/scripts/service-event-end
            fi
        else
            cru a "$SCRIPT_NAME" "*/1 * * * * $SCRIPT_PATH init-run"
        fi
    ;;
    "stop")
        cru d "$SCRIPT_NAME"

        [ -n "$PROCESS_PID" ] && kill "$PROCESS_PID_LIST"
    ;;
    "restart")
        if [ -f "/usr/sbin/helper.sh" ]; then # use service-event-end on Merlin firmware
            sh "$SCRIPT_PATH" stop
            sh "$SCRIPT_PATH" start
        else
            cru a "$SCRIPT_NAME" "*/1 * * * * $SCRIPT_PATH init-run restart"
        fi
    ;;
    *)
        echo "Usage: $0 run|start|stop|restart"
        exit 1
    ;;
esac
