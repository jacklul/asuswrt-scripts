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

readonly script_path="$(readlink -f "$0")"
readonly script_name="$(basename "$script_path" .sh)"
readonly script_dir="$(dirname "$script_path")"
readonly script_config="$script_dir/$script_name.conf"

SYSLOG_FILE="/tmp/syslog.log" # target syslog file to read
CACHE_FILE="/tmp/last_syslog_line" # where to store last parsed log line in case of crash
EXECUTE_COMMAND="" # command to execute in addition to build-in script (receives arguments: $1 = event, $2 = target)
SLEEP=1 # how to long to wait between each syslog reading iteration

# Chain names definitions, must be changed if they were modified in their scripts
readonly CHAINS_FORCEDNS="FORCEDNS"
readonly CHAINS_SAMBA_MASQUERADE="SAMBA_MASQUERADE"
readonly CHAINS_VPN_KILLSWITCH="VPN_KILLSWITCH"
readonly CHAINS_WGS_LANONLY="WGS_LANONLY"

if [ -f "$script_config" ]; then
    #shellcheck disable=SC1090
    . "$script_config"
fi

[ -f "/usr/sbin/helper.sh" ] && MERLIN="1"

lockfile() { #LOCKFILE_START#
    [ -z "$script_name" ] && script_name="$(basename "$0" .sh)"

    _lockfile="/var/lock/script-$script_name.lock"
    _pidfile="/var/run/script-$script_name.pid"
    _fd=100
    _fd_max=200

    if [ -n "$2" ]; then
        _lockfile="/var/lock/script-$script_name-$2.lock"
        _pidfile="/var/run/script-$script_name-$2.lock"
    fi

    [ -n "$3" ] && [ "$3" -eq "$3" ] && _fd="$3" && _fd_max="$3"
    [ -n "$4" ] && [ "$4" -eq "$4" ] && _fd_max="$4"

    [ ! -d /var/lock ] && { mkdir -p /var/lock || exit 1; }
    [ ! -d /var/run ] && { mkdir -p /var/run || exit 1; }

    _lockpid=
    [ -f "$_pidfile" ] && _lockpid="$(cat "$_pidfile")"

    case "$1" in
        "lockwait"|"lockfail"|"lockexit")
            if [ -n "$_lockpid" ] && ! grep -q "$script_name" "/proc/$_lockpid/cmdline" 2> /dev/null; then
                _lockpid=
            fi

            case "$1" in
                "lockfail"|"lockexit")
                    if [ -n "$_lockpid" ] && [ -f "/proc/$_lockpid/stat" ]; then
                        [ "$1" = "lockfail" ] && return 1
                        exit 1
                    fi
                ;;
            esac

            while [ -f "/proc/$$/fd/$_fd" ]; do
                _fd=$((_fd+1))

                [ "$_fd" -gt "$_fd_max" ] && { echo "Failed to acquire a lock - no available file descriptor"; exit 1; }
            done

            eval exec "$_fd>$_lockfile"

            case "$1" in
                "lockwait")
                    _lockwait=0
                    while ! flock -nx "$_fd" && { [ -z "$_lockpid" ] || [ -f "/proc/$_lockpid/stat" ] ; }; do #flock -x "$_fd"
                        sleep 1
                        if [ "$_lockwait" -ge 60 ]; then
                            echo "Failed to acquire a lock after 60 seconds"
                            exit 1
                        fi
                    done
                ;;
                "lockfail")
                    flock -nx "$_fd" || return 1
                ;;
                "lockexit")
                    flock -nx "$_fd" || exit 1
                ;;
            esac

            echo $$ > "$_pidfile"
            trap 'flock -u $_fd; rm -f "$_lockfile" "$_pidfile"; exit $?' INT TERM EXIT
        ;;
        "unlock")
            flock -u "$_fd"
            rm -f "$_lockfile" "$_pidfile"
            trap - INT TERM EXIT
        ;;
        "check")
            [ -n "$_lockpid" ] && [ -f "/proc/$_lockpid/stat" ] && return 0
            return 1
        ;;
        "kill")
            [ -n "$_lockpid" ] && [ -f "/proc/$_lockpid/stat" ] && kill -9 "$_lockpid" && return 0
            return 1
        ;;
    esac
} #LOCKFILE_END#

is_started_by_system() { #ISSTARTEDBYSYSTEM_START#
    _ppid=$PPID

    while true; do
        [ -z "$_ppid" ] && break
        _ppid=$(< "/proc/$_ppid/stat" awk '{print $4}')

        grep -q "cron" "/proc/$_ppid/comm" && return 0
        grep -q "hotplug" "/proc/$_ppid/comm" && return 0
        [ "$_ppid" -gt 1 ] || break
    done

    return 1
} #ISSTARTEDBYSYSTEM_END#

service_monitor() {
    [ ! -f "$SYSLOG_FILE" ] && { logger -st "$script_name" "Syslog log file does not exist: $SYSLOG_FILE"; exit 1; }

    lockfile lockfail || { echo "Already running! ($_lockpid)"; exit 1; }

    set -e

    logger -st "$script_name" "Started service event monitoring..."

    if [ -f "$CACHE_FILE" ]; then
        last_line="$(cat "$CACHE_FILE")"
    else
        last_line="$(wc -l < "$SYSLOG_FILE")"
        last_line="$((last_line+1))"
    fi

    while true; do
        total_lines="$(wc -l < "$SYSLOG_FILE")"
        if [ "$total_lines" -lt "$((last_line-1))" ]; then
            logger -st "$script_name" "Log file has been rotated, resetting line pointer..."
            last_line=1
            continue
        fi

        new_lines="$(tail "$SYSLOG_FILE" -n "+$last_line")"

        if [ -n "$new_lines" ]; then
            matching_lines="$(echo "$new_lines" | grep -En 'rc_service.*notify_rc' || echo '')"

            if [ -n "$matching_lines" ]; then
                last_line_old=$last_line

                IFS="$(printf '\n\b')"
                for new_line in $matching_lines; do
                    line_number="$(echo "$new_line" | cut -f1 -d:)"
                    last_line="$((last_line_old+line_number))"

                    events="$(echo "$new_line" | awk -F 'notify_rc ' '{print $2}')"

                    if [ -n "$init" ]; then
                        oldifs=$IFS
                        IFS=';'
                        for event in $events; do
                            if [ -n "$event" ]; then
                                event_action="$(echo "$event" | cut -d'_' -f1)"
                                event_target="$(echo "$event" | cut -d'_' -f2- | cut -d' ' -f1)"

                                logger -st "$script_name" "Running script (args: '${event_action}' '${event_target}')"

                                sh "$script_path" event "$event_action" "$event_target" &
                                [ -n "$EXECUTE_COMMAND" ] && "$EXECUTE_COMMAND" "$event_action" "$event_target" &
                            fi
                        done
                        IFS=$oldifs
                    fi
                done
            else
                total_lines="$(echo "$new_lines" | wc -l)"
                last_line="$((last_line+total_lines))"
            fi
        fi

        echo "$last_line" > "$CACHE_FILE"

        [ -z "$init" ] && init=1

        sleep "$SLEEP"
    done

    lockfile unlock
}

case "$1" in
    "run")
        [ -n "$MERLIN" ] && exit # Do not run on Asuswrt-Merlin firmware

        if is_started_by_system && [ "$2" != "nohup" ]; then
            nohup "$script_path" run nohup > /dev/null 2>&1 &
        else
            service_monitor
        fi
    ;;
    "event")
        # $2 = event, $3 = target
        case "$3" in
            "firewall"|"vpnc_dev_policy"|"pms_device"|"ftpd"|"ftpd_force"|"tftpd"|"aupnpc"|"chilli"|"CP"|"radiusd"|"webdav"|"enable_webdav"|"time"|"snmpd"|"vpnc"|"vpnd"|"pptpd"|"openvpnd"|"wgs"|"yadns"|"dnsfilter"|"tr"|"tor")
                if
                    [ -x "$script_dir/vpn-killswitch.sh" ] ||
                    [ -x "$script_dir/wgs-lanonly.sh" ] ||
                    [ -x "$script_dir/force-dns.sh" ] ||
                    [ -x "$script_dir/samba-masquerade.sh" ]
                then
                    if [ -z "$MERLIN" ]; then # do not perform sleep-checks on Asuswrt-Merlin firmware
                        timer=60; while { # wait till our chains disappear
                            iptables -nL "$CHAINS_VPN_KILLSWITCH" > /dev/null 2>&1 ||
                            iptables -nL "$CHAINS_WGS_LANONLY" > /dev/null 2>&1 ||
                            iptables -nL "$CHAINS_FORCEDNS" -t nat > /dev/null 2>&1 ||
                            iptables -nL "$CHAINS_SAMBA_MASQUERADE" -t nat > /dev/null 2>&1
                        } && [ "$timer" -ge 0 ]; do
                            timer=$((timer-1))
                            sleep 1
                        done
                    fi

                    [ -x "$script_dir/vpn-killswitch.sh" ] && sh "$script_dir/vpn-killswitch.sh" run &
                    [ -x "$script_dir/wgs-lanonly.sh" ] && sh "$script_dir/wgs-lanonly.sh" run &
                    [ -x "$script_dir/force-dns.sh" ] && sh "$script_dir/force-dns.sh" run &
                    [ -x "$script_dir/samba-masquerade.sh" ] && sh "$script_dir/samba-masquerade.sh" run &
                fi

                sh "$script_path" event restart custom_configs &
            ;;
            "allnet"|"net_and_phy"|"net"|"multipath"|"subnet"|"wan"|"wan_if"|"dslwan_if"|"dslwan_qis"|"dsl_wireless"|"wan_line"|"wan6"|"wan_connect"|"wan_disconnect"|"isp_meter")
                if
                    [ -x "$script_dir/usb-network.sh" ] ||
                    [ -x "$script_dir/extra-ip.sh" ] ||
                    [ -x "$script_dir/dynamic-dns.sh" ]
                then
                    if [ -z "$MERLIN" ]; then # do not perform sleep-checks on Asuswrt-Merlin firmware
                        timer=10; while { # wait until wan goes down
                            { [ "$(nvram get wan0_state_t)" = "2" ] || [ "$(nvram get wan0_state_t)" = "0" ] || [ "$(nvram get wan0_state_t)" = "5" ] ; } &&
                            { [ "$(nvram get wan1_state_t)" = "2" ] || [ "$(nvram get wan1_state_t)" = "0" ] || [ "$(nvram get wan1_state_t)" = "5" ] ; };
                        } && [ "$timer" -ge 0 ]; do
                            timer=$((timer-1))
                            sleep 1
                        done

                        timer=60; while { # wait until wan goes up
                            [ "$(nvram get wan0_state_t)" != "2" ] &&
                            [ "$(nvram get wan1_state_t)" != "2" ];
                        } && [ "$timer" -ge 0 ]; do
                            timer=$((timer-1))
                            sleep 1
                        done
                    fi

                    [ -x "$script_dir/usb-network.sh" ] && sh "$script_dir/usb-network.sh" run &
                    [ -x "$script_dir/extra-ip.sh" ] && sh "$script_dir/extra-ip.sh" run &
                    [ -x "$script_dir/dynamic-dns.sh" ] && sh "$script_dir/dynamic-dns.sh" run &
                fi

                # most services here also restart firewall and/or wireless and/or recreate configs so execute these too
                sh "$script_path" event restart wireless &
                sh "$script_path" event restart firewall &
                #sh "$script_path" event restart custom_configs & # this is already executed by 'restart firewall' event
            ;;
            "wireless")
                # probably a good idea to run this just in case
                [ -x "$script_dir/disable-wps.sh" ] && sh "$script_dir/disable-wps.sh" run &

                # this service event recreates rc_support so we have to re-run this script
                if [ -x "$script_dir/modify-features.sh" ]; then
                    if [ -f /tmp/rc_support.last ]; then
                        rc_support_last="$(cat /tmp/rc_support.last 2> /dev/null)"

                        if [ -z "$MERLIN" ]; then # do not perform sleep-checks on Asuswrt-Merlin firmware
                            timer=60; while { # wait till rc_support is modified
                                [ "$(nvram get rc_support)" = "$rc_support_last" ]
                            } && [ "$timer" -ge 0 ]; do
                                timer=$((timer-1))
                                sleep 1
                            done
                        fi
                    fi

                    sh "$script_dir/modify-features.sh" run &
                fi
            ;;
            "usb_idle")
                # re-run in case script exited due to USB idle being set and now it has been disabled
                [ -x "$script_dir/swap.sh" ] && sh "$script_dir/swap.sh" run &
            ;;
            "custom_configs"|"nasapps"|"ftpsamba"|"samba"|"samba_force"|"pms_account"|"media"|"dms"|"mt_daapd"|"upgrade_ate"|"mdns"|"dnsmasq"|"dhcpd"|"stubby"|"upnp"|"quagga")
                if [ -x "$script_dir/custom-configs.sh" ] && [ -z "$MERLIN" ]; then # Do not run custom-configs on Asuswrt-Merlin firmware as that functionality is already built-in
                    { sleep 5 && sh "$script_dir/custom-configs.sh" run; } &
                fi
            ;;
        esac

        # these do not follow the naming scheme ("ACTION_SERVICE")
        case "${2}_${3}" in
            "ipsec_set"|"ipsec_start"|"ipsec_restart")
                sh "$script_path" event restart firewall
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

            if ! grep -q "$script_path" /jffs/scripts/service-event-end; then
                echo "$script_path event \"\$1\" \"\$2\" & # jacklul/asuswrt-scripts" >> /jffs/scripts/service-event-end
            fi
        else
            if [ -x "$script_dir/cron-queue.sh" ]; then
                sh "$script_dir/cron-queue.sh" add "$script_name" "$script_path run"
            else
                cru a "$script_name" "*/1 * * * * $script_path run"
            fi

            if is_started_by_system; then
                sh "$script_path" run
            else
                echo "Will launch within one minute by cron..."
            fi
        fi
    ;;
    "stop")
        [ -x "$script_dir/cron-queue.sh" ] && sh "$script_dir/cron-queue.sh" remove "$script_name"
        cru d "$script_name"

        lockfile kill
    ;;
    "restart")
        sh "$script_path" stop
        sh "$script_path" start
    ;;
    *)
        echo "Usage: $0 run|start|stop|restart"
        exit 1
    ;;
esac
