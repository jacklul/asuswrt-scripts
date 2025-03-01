#!/bin/sh
# Made by Jack'lul <jacklul.github.io>
#
# Execute commands when specific service events occurs
#
# Implements basic service-event script handler from Asuswrt-Merlin:
#  https://github.com/RMerl/asuswrt-merlin.ng/wiki/User-scripts
#
# There is no blocking so there is no guarantee that this script will run before the event happens.
# You will probably want add extra code if you want to run code after the event happens.
# Scripts from this repository are already handled by the build-in script.
#

#jacklul-asuswrt-scripts-update=service-event.sh
#shellcheck disable=SC2155

readonly SCRIPT_PATH="$(readlink -f "$0")"
readonly SCRIPT_NAME="$(basename "$SCRIPT_PATH" .sh)"
readonly SCRIPT_DIR="$(dirname "$SCRIPT_PATH")"
readonly SCRIPT_CONFIG="$SCRIPT_DIR/$SCRIPT_NAME.conf"
readonly SCRIPT_TAG="$(basename "$SCRIPT_PATH")"

SYSLOG_FILE="/tmp/syslog.log" # target syslog file to read
CACHE_FILE="/tmp/last_syslog_line" # where to store last parsed log line in case of crash
EXECUTE_COMMAND="" # command to execute in addition to build-in script (receives arguments: $1 = event, $2 = target)
SLEEP=1 # how to long to wait between each syslog reading iteration

# Chain names definitions, must be changed if they were modified in their scripts
CHAINS_FORCEDNS="FORCEDNS"
CHAINS_SAMBA_MASQUERADE="SAMBA_MASQUERADE"
CHAINS_VPN_KILLSWITCH="VPN_KILLSWITCH"
CHAINS_WGS_LANONLY="WGS_LANONLY"

if [ -f "$SCRIPT_CONFIG" ]; then
    #shellcheck disable=SC1090
    . "$SCRIPT_CONFIG"
fi

[ -f "/usr/sbin/helper.sh" ] && MERLIN="1"

lockfile() { #LOCKFILE_START#
    _LOCKFILE="/var/lock/script-$SCRIPT_NAME.lock"
    _PIDFILE="/var/run/script-$SCRIPT_NAME.pid"
    _FD=100
    _FD_MAX=200

    if [ -n "$2" ]; then
        _LOCKFILE="/var/lock/script-$SCRIPT_NAME-$2.lock"
        _PIDFILE="/var/run/script-$SCRIPT_NAME-$2.lock"
    fi

    [ -n "$3" ] && [ "$3" -eq "$3" ] && _FD="$3" && _FD_MAX="$3"
    [ -n "$4" ] && [ "$4" -eq "$4" ] && _FD_MAX="$4"

    [ ! -d /var/lock ] && mkdir -p /var/lock
    [ ! -d /var/run ] && mkdir -p /var/run

    _LOCKPID=
    [ -f "$_PIDFILE" ] && _LOCKPID="$(cat "$_PIDFILE")"

    case "$1" in
        "lockwait"|"lockfail"|"lockexit")
            while [ -f "/proc/$$/fd/$_FD" ]; do
                #echo "File descriptor $_FD is already in use ($(readlink -f "/proc/$$/fd/$_FD"))"
                _FD=$((_FD+1))

                [ "$_FD" -gt "$_FD_MAX" ] && { echo "Failed to find available file descriptor"; exit 1; }
            done

            eval exec "$_FD>$_LOCKFILE"

            case "$1" in
                "lockwait")
                    _LOCK_WAITED=0
                    while ! flock -nx "$_FD"; do #flock -x "$_FD"
                        sleep 1
                        if [ "$_LOCK_WAITED" -ge 60 ]; then
                            echo "Failed to acquire a lock after 60 seconds"
                            exit 1
                        fi
                    done
                ;;
                "lockfail")
                    flock -nx "$_FD" || return 1
                ;;
                "lockexit")
                    flock -nx "$_FD" || exit 1
                ;;
            esac

            echo $$ > "$_PIDFILE"
            trap 'flock -u $_FD; rm -f "$_LOCKFILE" "$_PIDFILE"; exit $?' INT TERM EXIT
        ;;
        "unlock")
            flock -u "$_FD"
            rm -f "$_LOCKFILE" "$_PIDFILE"
            trap - INT TERM EXIT
        ;;
        "check")
            [ -n "$_LOCKPID" ] && [ -f "/proc/$_LOCKPID/stat" ] && return 0
            return 1
        ;;
        "kill")
            [ -n "$_LOCKPID" ] && [ -f "/proc/$_LOCKPID/stat" ] && kill -9 "$_LOCKPID" && return 0
            return 1
        ;;
    esac
} #LOCKFILE_END#

is_started_by_system() { #ISSTARTEDBYSYSTEM_START#
    _PPID=$PPID
    while true; do
        [ -z "$_PPID" ] && break
        _PPID=$(< "/proc/$_PPID/stat" awk '{print $4}')

        grep -q "cron" "/proc/$_PPID/comm" && return 0
        grep -q "hotplug" "/proc/$_PPID/comm" && return 0
        [ "$_PPID" -gt 1 ] || break
    done

    return 1
} #ISSTARTEDBYSYSTEM_END#

service_monitor() {
    [ ! -f "$SYSLOG_FILE" ] && { logger -st "$SCRIPT_TAG" "Syslog log file does not exist: $SYSLOG_FILE"; exit 1; }

    lockfile lockfail || { echo "Already running! ($_LOCKPID)"; exit 1; }

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

                                logger -st "$SCRIPT_TAG" "Running script (args: '${EVENT_ACTION}' '${EVENT_TARGET}')"

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

    lockfile unlock
}

case "$1" in
    "run")
        [ -n "$MERLIN" ] && exit # Do not run on Asuswrt-Merlin firmware

        if is_started_by_system && [ "$2" != "nohup" ]; then
            nohup "$SCRIPT_PATH" run nohup > /dev/null 2>&1 &
        else
            service_monitor
        fi
    ;;
    "event")
        # $2 = event, $3 = target
        case "$3" in
            "firewall"|"vpnc_dev_policy"|"pms_device"|"ftpd"|"ftpd_force"|"tftpd"|"aupnpc"|"chilli"|"CP"|"radiusd"|"webdav"|"enable_webdav"|"time"|"snmpd"|"vpnc"|"vpnd"|"pptpd"|"openvpnd"|"wgs"|"yadns"|"dnsfilter"|"tr"|"tor")
                if
                    [ -x "$SCRIPT_DIR/vpn-killswitch.sh" ] ||
                    [ -x "$SCRIPT_DIR/wgs-lanonly.sh" ] ||
                    [ -x "$SCRIPT_DIR/force-dns.sh" ] ||
                    [ -x "$SCRIPT_DIR/samba-masquerade.sh" ]
                then
                    if [ -z "$MERLIN" ]; then # do not perform sleep-checks on Asuswrt-Merlin firmware
                        TIMER=0; while { # wait till our chains disappear
                            iptables -nL "$CHAINS_VPN_KILLSWITCH" > /dev/null 2>&1 ||
                            iptables -nL "$CHAINS_WGS_LANONLY" > /dev/null 2>&1 ||
                            iptables -nL "$CHAINS_FORCEDNS" -t nat > /dev/null 2>&1 ||
                            iptables -nL "$CHAINS_SAMBA_MASQUERADE" -t nat > /dev/null 2>&1
                        } && [ "$TIMER" -lt 60 ]; do
                            TIMER=$((TIMER+1))
                            sleep 1
                        done
                    fi

                    [ -x "$SCRIPT_DIR/vpn-killswitch.sh" ] && sh "$SCRIPT_DIR/vpn-killswitch.sh" run &
                    [ -x "$SCRIPT_DIR/wgs-lanonly.sh" ] && sh "$SCRIPT_DIR/wgs-lanonly.sh" run &
                    [ -x "$SCRIPT_DIR/force-dns.sh" ] && sh "$SCRIPT_DIR/force-dns.sh" run &
                    [ -x "$SCRIPT_DIR/samba-masquerade.sh" ] && sh "$SCRIPT_DIR/samba-masquerade.sh" run &
                fi

                sh "$SCRIPT_PATH" event restart custom_configs &
            ;;
            "allnet"|"net_and_phy"|"net"|"multipath"|"subnet"|"wan"|"wan_if"|"dslwan_if"|"dslwan_qis"|"dsl_wireless"|"wan_line"|"wan6"|"wan_connect"|"wan_disconnect"|"isp_meter")
                if
                    [ -x "$SCRIPT_DIR/usb-network.sh" ] ||
                    [ -x "$SCRIPT_DIR/extra-ip.sh" ] ||
                    [ -x "$SCRIPT_DIR/dynamic-dns.sh" ]
                then
                    if [ -z "$MERLIN" ]; then # do not perform sleep-checks on Asuswrt-Merlin firmware
                        TIMER=0; while { # wait until wan goes down
                            { [ "$(nvram get wan0_state_t)" = "2" ] || [ "$(nvram get wan0_state_t)" = "0" ] || [ "$(nvram get wan0_state_t)" = "5" ] ; } &&
                            { [ "$(nvram get wan1_state_t)" = "2" ] || [ "$(nvram get wan1_state_t)" = "0" ] || [ "$(nvram get wan1_state_t)" = "5" ] ; };
                        } && [ "$TIMER" -lt 10 ]; do
                            TIMER=$((TIMER+1))
                            sleep 1
                        done

                        TIMER=0; while { # wait until wan goes up
                            [ "$(nvram get wan0_state_t)" != "2" ] &&
                            [ "$(nvram get wan1_state_t)" != "2" ];
                        } && [ "$TIMER" -lt 60 ]; do
                            TIMER=$((TIMER+1))
                            sleep 1
                        done
                    fi

                    [ -x "$SCRIPT_DIR/usb-network.sh" ] && sh "$SCRIPT_DIR/usb-network.sh" run &
                    [ -x "$SCRIPT_DIR/extra-ip.sh" ] && sh "$SCRIPT_DIR/extra-ip.sh" run &
                    [ -x "$SCRIPT_DIR/dynamic-dns.sh" ] && sh "$SCRIPT_DIR/dynamic-dns.sh" run &
                fi

                # most services here also restart firewall and/or wireless and/or recreate configs so execute these too
                sh "$SCRIPT_PATH" event restart wireless &
                sh "$SCRIPT_PATH" event restart firewall &
                #sh "$SCRIPT_PATH" event restart custom_configs & # this is already executed by 'restart firewall' event
            ;;
            "wireless")
                # probably a good idea to run this just in case
                [ -x "$SCRIPT_DIR/disable-wps.sh" ] && sh "$SCRIPT_DIR/disable-wps.sh" run &

                # this service event recreates rc_support so we have to re-run this script
                if [ -x "$SCRIPT_DIR/modify-features.sh" ]; then
                    if [ -f /tmp/rc_support.last ]; then
                        RC_SUPPORT_LAST="$(cat /tmp/rc_support.last)"

                        if [ -z "$MERLIN" ]; then # do not perform sleep-checks on Asuswrt-Merlin firmware
                            TIMER=0; while { # wait till rc_support is modified
                                [ "$(nvram get rc_support)" = "$RC_SUPPORT_LAST" ]
                            } && [ "$TIMER" -lt "60" ]; do
                                TIMER=$((TIMER+1))
                                sleep 1
                            done
                        fi
                    fi

                    sh "$SCRIPT_DIR/modify-features.sh" run &
                fi
            ;;
            "usb_idle")
                # re-run in case script exited due to USB idle being set and now it has been disabled
                [ -x "$SCRIPT_DIR/swap.sh" ] && sh "$SCRIPT_DIR/swap.sh" run &
            ;;
            "custom_configs"|"nasapps"|"ftpsamba"|"samba"|"samba_force"|"pms_account"|"media"|"dms"|"mt_daapd"|"upgrade_ate"|"mdns"|"dnsmasq"|"dhcpd"|"stubby"|"upnp"|"quagga")
                if [ -x "$SCRIPT_DIR/custom-configs.sh" ] && [ -z "$MERLIN" ]; then # Do not run custom-configs on Asuswrt-Merlin firmware as that functionality is already built-in
                    { sleep 5 && sh "$SCRIPT_DIR/custom-configs.sh" run; } &
                fi
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
    "start")
        if [ -n "$MERLIN" ]; then # use service-event-end on Asuswrt-Merlin firmware
            if [ ! -f /jffs/scripts/service-event-end ]; then
                cat <<EOT > /jffs/scripts/service-event-end
#!/bin/sh

EOT
                chmod 0755 /jffs/scripts/service-event-end
            fi

            if ! grep -q "$SCRIPT_PATH" /jffs/scripts/service-event-end; then
                echo "$SCRIPT_PATH event \"\$1\" \"\$2\" & # jacklul/asuswrt-scripts" >> /jffs/scripts/service-event-end
            fi
        else
            if [ -x "$SCRIPT_DIR/cron-queue.sh" ]; then
                sh "$SCRIPT_DIR/cron-queue.sh" add "$SCRIPT_NAME" "$SCRIPT_PATH run"
            else
                cru a "$SCRIPT_NAME" "*/1 * * * * $SCRIPT_PATH run"
            fi

            if is_started_by_system; then
                sh "$SCRIPT_PATH" run
            else
                echo "Will launch within one minute by cron..."
            fi
        fi
    ;;
    "stop")
        [ -x "$SCRIPT_DIR/cron-queue.sh" ] && sh "$SCRIPT_DIR/cron-queue.sh" remove "$SCRIPT_NAME"
        cru d "$SCRIPT_NAME"

        lockfile kill
    ;;
    "restart")
        sh "$SCRIPT_PATH" stop
        sh "$SCRIPT_PATH" start
    ;;
    *)
        echo "Usage: $0 run|start|stop|restart"
        exit 1
    ;;
esac
