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
# Scripts from this repository are already integrated.
#

#jas-update=service-event.sh
#shellcheck disable=SC2155
#shellcheck source=./common.sh
readonly common_script="$(dirname "$0")/common.sh"
if [ -f "$common_script" ]; then . "$common_script"; else { echo "$common_script not found"; exit 1; } fi

SYSLOG_FILE="/tmp/syslog.log" # target syslog file to read
SLEEP=1 # how to long to wait between each syslog reading iteration, increase to reduce load but introduce delays in action execution
NO_INTEGRATION=false # set to true to disable integration with jacklul/asuswrt-scripts, this can potentially break their functionality
EXECUTE_COMMAND="" # command to execute in addition to build-in script (receives arguments: $1 = event, $2 = target, $3 = normalized event name)
STATE_FILE="$TMP_DIR/$script_name" # where to store last parsed log line in case of crash

load_script_config

is_merlin_firmware && merlin=true
readonly CHECK_CHAIN="jas-$script_name"
readonly CHECK_IP="127.83.69.33/8" # asci SE! = service event !

custom_checks() {
    change_interface=false
    change_firewall=false
    change_wan=false

    if ! ip addr show dev lo | grep -Fq "inet $CHECK_IP "; then
        if [ -n "$change_interface_detected" ]; then
            ip -4 addr add "$CHECK_IP" dev lo label lo:se
            change_interface=true
            change_interface_detected=
        else
            change_interface_detected=true
        fi
    fi

    if ! iptables -nL "$CHECK_CHAIN" > /dev/null 2>&1; then
        if [ -n "$change_firewall_detected" ]; then
            iptables -N "$CHECK_CHAIN"
            change_firewall=true
            change_firewall_detected=
        else
            change_firewall_detected=true
        fi
    fi

    # Currently disabled as it triggers on script start because $wan_state_last is not stored persistently
    #wan_state="$(nvram get wan0_state_t 2> /dev/null)$(nvram get wan1_state_t 2> /dev/null)"
    #if [ "$wan_state" != "$wan_state_last" ]; then
    #    if [ -n "$change_wan_detected" ]; then
    #        wan_state_last="$wan_state"
    #        change_wan=true
    #        change_wan_detected=
    #    else
    #        change_wan_detected=true
    #    fi
    #fi

    if [ "$change_interface" = true ] || [ "$change_firewall" = true ] || [ "$change_wan" = true ]; then
        return 1
    fi

    return 0
}

trigger_event() {
    _action="$1"
    _target="$2"

    if [ "$3" = "ccheck" ]; then # this argument disables event verification timers in the event handler
        lockfile check "event_${_action}_${_target}" && return # already processing this event

        logecho "Running script (args: '$_action' '$_target') *" true
    else
        logecho "Running script (args: '$_action' '$_target')" true
    fi

    sh "$script_path" event "$_action" "$_target" "$3" &
}

service_monitor() {
    [ ! -f "$SYSLOG_FILE" ] && { logecho "Error: Syslog log file does not exist: $SYSLOG_FILE"; exit 1; }

    lockfile lockfail || { echo "Already running! ($lockpid)"; exit 1; }

    set -e

    logecho "Started service event monitoring..." true

    if [ -f "$STATE_FILE" ]; then
        _last_line="$(cat "$STATE_FILE")"
        _initialized=true
    else
        _last_line="$(wc -l < "$SYSLOG_FILE")"
        _last_line="$((_last_line+1))"
        custom_checks || true
    fi

    while true; do
        _total_lines="$(wc -l < "$SYSLOG_FILE")"
        if [ "$_total_lines" -lt "$((_last_line-1))" ]; then
            logecho "Log file has been rotated, resetting line pointer..." true
            _last_line=1
            continue
        fi

        _new_lines="$(tail "$SYSLOG_FILE" -n "+$_last_line")"

        if [ -n "$_new_lines" ]; then
            _matching_lines="$(echo "$_new_lines" | grep -En 'rc_service.*notify_rc' || echo '')"

            if [ -n "$_matching_lines" ]; then
                _last_line_old=$_last_line

                IFS="$(printf '\n\b')"
                for _new_line in $_matching_lines; do
                    _line_number="$(echo "$_new_line" | cut -d ':' -f 1)"
                    _last_line="$((_last_line_old+_line_number))"

                    if [ -n "$_initialized" ]; then
                        _events="$(echo "$_new_line" | awk -F 'notify_rc ' '{print $2}')"

                        _oldIFS=$IFS
                        IFS=';'
                        for _event in $_events; do
                            if [ -n "$_event" ]; then
                                _event_action="$(echo "$_event" | cut -d '_' -f 1)"
                                _event_target="$(echo "$_event" | cut -d '_' -f 2- | cut -d ' ' -f 1)"

                                trigger_event "$_event_action" "$_event_target"
                                _event_triggered=true
                            fi
                        done
                        IFS=$_oldIFS
                    fi
                done
            else
                _total_lines="$(echo "$_new_lines" | wc -l)"
                _last_line="$((_last_line+_total_lines))"
            fi
        fi

        if [ -z "$_event_triggered" ] && ! custom_checks; then
            if [ "$change_interface" = true ] || [ "$change_wan" = true ]; then
                trigger_event "restart" "net" "ccheck"
            fi

            if [ "$change_firewall" = true ]; then
                trigger_event "restart" "firewall" "ccheck"
            fi
        fi

        echo "$_last_line" > "$STATE_FILE"

        [ -z "$_initialized" ] && _initialized=true
        _event_triggered=

        sleep "$SLEEP"
    done

    lockfile unlock
}

integrated_event() {
    [ "$NO_INTEGRATION" = true ] && return

    # $1 = type, $2 = event, $3 = target, $4 = extra
    case "$1" in
        "firewall")
            execute_script_basename "vpn-kill-switch.sh" run
            execute_script_basename "vpn-firewall.sh" run
            execute_script_basename "wgs-lan-only.sh" run
            execute_script_basename "force-dns.sh" run
            execute_script_basename "vpn-ip-routes.sh" run
            execute_script_basename "vpn-vserver.sh" run
            execute_script_basename "vpn-samba.sh" run
        ;;
        "network")
            execute_script_basename "usb-network.sh" run
            execute_script_basename "extra-ip.sh" run
            execute_script_basename "dynamic-dns.sh" run

            # most services here also restart firewall, wireless and/or recreate configs so execute these too
            integrated_event firewall "$2" "$3" "$4"
            integrated_event wireless "$2" "$3" "$4"
            integrated_event custom_configs "$2" "$3" "$4"
        ;;
        "wireless")
            # probably a good idea to run this just in case
            execute_script_basename "disable-wps.sh" run

            # this service event recreates rc_support so we have to re-run this script
            _tmp_script_path="$(resolve_script_basename "modify-features.sh")"
            if [ -n "$_tmp_script_path" ] && [ -x "$_tmp_script_path" ]; then
                if [ -z "$merlin" ] && [ "$4" != "ccheck" ]; then
                    timer=30; while { # wait till rc_support is modified
                        sh "$_tmp_script_path" check
                    } && [ "$timer" -ge 0 ]; do
                        timer=$((timer-1))
                        sleep 1
                    done
                fi

                sh "$_tmp_script_path" run
            fi
        ;;
        "usb_idle")
            # re-run in case script exited due to USB idle being set and now it has been disabled
            execute_script_basename "swap.sh" run
        ;;
        "custom_configs")
            _tmp_script_path="$(resolve_script_basename "custom-configs.sh")"
            if [ -n "$_tmp_script_path" ] && [ -x "$_tmp_script_path" ] && [ -z "$merlin" ]; then
                # delay the execution to let the calling service create their config
                { sleep 10 && sh "$_tmp_script_path" run; } &
            fi
        ;;
    esac
}

run_in_background() {
    [ -n "$merlin" ] && exit # Do not run on Asuswrt-Merlin firmware
    lockfile check && { echo "Already running! ($lockpid)"; exit 1; }

    if is_started_by_system && [ "$PPID" -ne 1 ]; then
        nohup "$script_path" run > /dev/null 2>&1 &
    else
        service_monitor
    fi
}

case "$1" in
    "run")
        run_in_background
    ;;
    "event")
        if [ "$4" = "ccheck" ]; then
            lockfile lockfail "event_${2}_${3}" || { echo "Error: This event is already being processed (args: '$2' '$3')"; exit 1; }
        else
            lockfile lockwait "event_${2}_${3}"
        fi

        event="$3"

        # $2 = event, $3 = target, $4 = extra
        case "$3" in
            "firewall"|"vpnc_dev_policy"|"pms_device"|"ftpd"|"ftpd_force"|"tftpd"|"aupnpc"|"chilli"|"CP"|"radiusd"|"webdav"|"enable_webdav"|"time"|"snmpd"|"vpnc"|"vpnd"|"pptpd"|"openvpnd"|"wgs"|"yadns"|"dnsfilter"|"tr"|"tor")
                event=firewall

                if [ -z "$merlin" ] && [ "$4" != "ccheck" ]; then
                    timer=10; while { # wait till our chains disappear
                        iptables -nL "$CHECK_CHAIN" > /dev/null 2>&1
                    } && [ "$timer" -ge 0 ]; do
                        timer=$((timer-1))
                        sleep 1
                    done
                fi

                integrated_event firewall "$2" "$3" "$4"
            ;;
            "allnet"|"net_and_phy"|"net"|"multipath"|"subnet"|"wan"|"wan_if"|"dslwan_if"|"dslwan_qis"|"dsl_wireless"|"wan_line"|"wan6"|"wan_connect"|"wan_disconnect"|"isp_meter")
                event=network

                if [ -z "$merlin" ] && [ "$4" != "ccheck" ]; then
                    timer=10; while { # wait until wan goes down
                        { [ "$(nvram get wan0_state_t)" = "2" ] || [ "$(nvram get wan0_state_t)" = "0" ] || [ "$(nvram get wan0_state_t)" = "5" ] ; } &&
                        { [ "$(nvram get wan1_state_t)" = "2" ] || [ "$(nvram get wan1_state_t)" = "0" ] || [ "$(nvram get wan1_state_t)" = "5" ] ; };
                    } && [ "$timer" -ge 0 ]; do
                        timer=$((timer-1))
                        sleep 1
                    done

                    timer=30; while { # wait until wan goes up
                        [ "$(nvram get wan0_state_t)" != "2" ] &&
                        [ "$(nvram get wan1_state_t)" != "2" ];
                    } && [ "$timer" -ge 0 ]; do
                        timer=$((timer-1))
                        sleep 1
                    done
                fi

                integrated_event network "$2" "$3" "$4"
            ;;
            "wireless")
                integrated_event wireless "$2" "$3" "$4"
            ;;
            "usb_idle")
                integrated_event usb_idle "$2" "$3" "$4"
            ;;
            "custom_configs"|"nasapps"|"ftpsamba"|"samba"|"samba_force"|"pms_account"|"media"|"dms"|"mt_daapd"|"upgrade_ate"|"mdns"|"dnsmasq"|"dhcpd"|"stubby"|"upnp"|"quagga")
                event=custom_configs
                integrated_event custom_configs "$2" "$3" "$4"
            ;;
        esac

        case "${2}_${3}" in
            "ipsec_set"|"ipsec_start"|"ipsec_restart") # these do not follow the naming scheme ("<ACTION>_<SERVICE>")
                event=firewall
                integrated_event firewall "$2" "$3" "$4"
            ;;
        esac

        [ -n "$EXECUTE_COMMAND" ] && "$EXECUTE_COMMAND" "$2" "$3" "$event"

        lockfile unlock "event_${2}_${3}"
        exit
    ;;
    "start")
        if [ -n "$merlin" ]; then # use service-event-end on Asuswrt-Merlin firmware
            if [ ! -f /jffs/scripts/service-event-end ]; then
                cat <<EOT > /jffs/scripts/service-event-end
#!/bin/sh

EOT
                chmod 0755 /jffs/scripts/service-event-end
            fi

            if ! grep -Fq "$script_path" /jffs/scripts/service-event-end; then
                echo "$script_path event \"\$1\" \"\$2\" & # https://github.com/jacklul/asuswrt-scripts" >> /jffs/scripts/service-event-end
            fi
        else
            crontab_entry add "*/1 * * * * $script_path run"

            if is_started_by_system; then
                run_in_background
            else
                echo "Will launch within one minute by cron..."
            fi
        fi
    ;;
    "stop")
        crontab_entry delete
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
