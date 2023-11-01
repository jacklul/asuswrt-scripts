# Custom scripts for AsusWRT

This uses known `script_usbmount` NVRAM variable to run "startup" script on USB mount event that starts things out.

Obviously this requires some kind of USB storage plugged into the router for this to work, you don't need it on Asuswrt-Merlin though - just start the scripts from [services-start script](https://github.com/RMerl/asuswrt-merlin.ng/wiki/User-scripts#services-start).

Everything here was tested on **RT-AX58U v2** on official **388.2** firmware (**3.0.0.4.388.22525** to be precise), there is no guarantee that everything will work on non-AX routers and on lower firmware versions. Some informations were pulled from **GPL_RT-AX58U_3.0.0.4.388.22525-gd35b8fe** sources.

**If your router is not executing commands from `script_usbmount` NVRAM variable on USB mount - [look here](/asusware-usbmount) for a workaround.**

## Installation

Install startup script:

```bash
curl -fsSL "https://raw.githubusercontent.com/jacklul/asuswrt-scripts/master/scripts-startup.sh" -o /jffs/scripts-startup.sh
/bin/sh /jffs/scripts-startup.sh install
```

_If you would like for it to be called differently you can rename it before running it._

Install scripts you want to use from [section below](#available-scripts).

# Available scripts

You can override config variables for scripts by creating `.conf` with the same base name as the script.

Remember to mark the scripts as executable after installing, you can do it in one command like this:
```sh
chmod +x /jffs/scripts/*.sh
```

---

## [`conditional-reboot.sh`](/scripts/conditional-reboot.sh)

This script will reboot your router at specified time if it's been running for fixed amount of time.

By default, reboot happens at 5AM when uptime exceeds 7 days.

```sh
curl -fsSL "https://raw.githubusercontent.com/jacklul/asuswrt-scripts/master/scripts/conditional-reboot.sh" -o /jffs/scripts/conditional-reboot.sh
```

## [`custom-configs.sh`](/scripts/custom-configs.sh)

This script implements [Custom config files from Merlin firmware](https://github.com/RMerl/asuswrt-merlin.ng/wiki/Custom-config-files) that allows you to use custom config files for certain services.

Supported config files:
- avahi-daemon.conf
- dnsmasq.conf
- minidlna.conf
- profile (profile.add only)
- smb.conf
- vsftpd.conf

_NOTE: Usage of Samba, FTP and Media services without any USB storage requires `nvram set usb_debug=1`!_

Recommended to use [`service-event.sh`](#user-content-service-eventsh) as well.

```sh
curl -fsSL "https://raw.githubusercontent.com/jacklul/asuswrt-scripts/master/scripts/custom-configs.sh" -o /jffs/scripts/custom-configs.sh
```

## [`disable-wps.sh`](/scripts/disable-wps.sh)

This script does exactly what you would expect - makes sure WPS stays disabled.

By default, runs check at boot and at 00:00, when `service-event.sh` is used also runs every time wireless is restarted.

Recommended to use [`service-event.sh`](#user-content-service-eventsh) as well.

```sh
curl -fsSL "https://raw.githubusercontent.com/jacklul/asuswrt-scripts/master/scripts/disable-wps.sh" -o /jffs/scripts/disable-wps.sh
```

## [`dynamic-dns.sh`](/scripts/dynamic-dns.sh)

This script implements [custom DDNS feature from Merlin firmware](https://github.com/RMerl/asuswrt-merlin.ng/wiki/DDNS-services#using-one-of-the-services-supported-by-in-a-dyn-but-not-by-the-asuswrt-merlin-webui) that allows you to use custom [Inadyn](https://github.com/troglobit/inadyn) config file.

Checks every minute for new IP in NVRAM variable `wan0_ipaddr`. You can alternatively configure it to use website API like "[ipecho.net/plain](https://ipecho.net/plain)".

On Merlin firmware you should call this script from `ddns-start` with `force` argument instead of `start`.

Recommended to use [`service-event.sh`](#user-content-service-eventsh) as well.

```sh
curl -fsSL "https://raw.githubusercontent.com/jacklul/asuswrt-scripts/master/scripts/dynamic-dns.sh" -o /jffs/scripts/dynamic-dns.sh
```

## [`entware.sh`](/scripts/entware.sh)

This script installs and enables Entware, even in RAM (`/tmp`).

When installing to `/tmp` it will automatically install specified packages and copy contents from `/jffs/entware` to `/opt`.

Recommended to use [`hotplug-event.sh`](#user-content-hotplug-eventsh) as well.

```sh
curl -fsSL "https://raw.githubusercontent.com/jacklul/asuswrt-scripts/master/scripts/entware.sh" -o /jffs/scripts/entware.sh
```

## [`force-dns.sh`](/scripts/force-dns.sh)

This script will force specified DNS server to be used by LAN and Guest WiFi, can also prevent clients from querying the router's DNS server.

This script can be very useful when running Pi-hole in your LAN.

Recommended to use [`service-event.sh`](#user-content-service-eventsh) as well.

```sh
curl -fsSL "https://raw.githubusercontent.com/jacklul/asuswrt-scripts/master/scripts/force-dns.sh" -o /jffs/scripts/force-dns.sh
```

## [`guest-password.sh`](/scripts/guest-password.sh)

This script rotates Guest WiFi passwords for specified guest networks.

```sh
curl -fsSL "https://raw.githubusercontent.com/jacklul/asuswrt-scripts/master/scripts/guest-password.sh" -o /jffs/scripts/guest-password.sh
```

## [`hotplug-event.sh`](/scripts/hotplug-event.sh)

This script handles hotplug events.

By default, integrates with all scripts present in this repository.

```sh
curl -fsSL "https://raw.githubusercontent.com/jacklul/asuswrt-scripts/master/scripts/hotplug-event.sh" -o /jffs/scripts/hotplug-event.sh
```

## [`led-control.sh`](/scripts/led-control.sh)

**Warning: this script is not complete and will probably not work on stock firmware (should work on Merlin), see note in the script.**

This script implements [scheduled LED control](https://github.com/RMerl/asuswrt-merlin.ng/wiki/Scheduled-LED-control).

By default, LEDs shutdown at 00:00 and turn on at 06:00.

```sh
curl -fsSL "https://raw.githubusercontent.com/jacklul/asuswrt-scripts/master/scripts/led-control.sh" -o /jffs/scripts/led-control.sh
```

## [`modify-features.sh`](/scripts/modify-features.sh)

This script modifies `rc_support` NVRAM variable to enable/disable some features, this is mainly for hiding Web UI menus and tabs.

A good place to look for potential values are `init.c` and `state.js` files in the firmware sources.

Recommended to use [`service-event.sh`](#user-content-service-eventsh) as well.

```sh
curl -fsSL "https://raw.githubusercontent.com/jacklul/asuswrt-scripts/master/scripts/modify-features.sh" -o /jffs/scripts/modify-features.sh
```

## [`modify-webui.sh`](/scripts/modify-webui.sh)

This script modifies some web UI elements.

Currently applied modifications:
- display CPU temperature on the system status screen (with realtime updates)
- show connect QR code on guest network edit screen and hide the passwords on the main screen
- add `notrendmicro` rc_support option that hides all Trend Micro services, **Speed Test** will be moved to **Network Tools** menu (to be used with [`modify-features.sh`](#user-content-modify-featuressh))

```sh
curl -fsSL "https://raw.githubusercontent.com/jacklul/asuswrt-scripts/master/scripts/modify-webui.sh" -o /jffs/scripts/modify-webui.sh
```

## [`netboot-tftp.sh`](/scripts/netboot-tftp.sh)

Automatically download specified files from [netboot.xyz](https://netboot.xyz).

This and [`custom-configs.sh`](#user-content-custom-configssh) can help you setup a **netboot.xyz** PXE server on the router.

```sh
curl -fsSL "https://raw.githubusercontent.com/jacklul/asuswrt-scripts/master/scripts/netboot-tftp.sh" -o /jffs/scripts/netboot-tftp.sh
```

## [`process-killer.sh`](/scripts/process-killer.sh)

This script can kill processes by their names, unfortunately on stock most of them will restart, there is an attempt to prevent that in that script but it is not guaranteed to work.

```sh
curl -fsSL "https://raw.githubusercontent.com/jacklul/asuswrt-scripts/master/scripts/process-killer.sh" -o /jffs/scripts/process-killer.sh
```

## [`rclone-backup.sh`](/scripts/rclone-backup.sh)

This script can backup all NVRAM variables and selected `/jffs` contents to cloud service using [Rclone](https://github.com/rclone/rclone).

You have to download the binary and place it on the USB drive. If you installed it through the Entware then it will be automatically detected, alternatively it will install it when it detects Entware installation (then remove it after the job is done - this feature is targeted for Entware in `/tmp`).

[Example backup list](/examples/rclone-backup.list) that can be used with this script.

```sh
curl -fsSL "https://raw.githubusercontent.com/jacklul/asuswrt-scripts/master/scripts/rclone-backup.sh" -o /jffs/scripts/rclone-backup.sh
```

## [`samba-masquerade.sh`](/scripts/samba-masquerade.sh)

Enables masquerade for Samba ports to allow VPN clients to connect to your LAN shares.

By default, default networks for WireGuard, OpenVPN and IPSec are set.

Recommended to use [`service-event.sh`](#user-content-service-eventsh) as well.

```sh
curl -fsSL "https://raw.githubusercontent.com/jacklul/asuswrt-scripts/master/scripts/samba-masquerade.sh" -o /jffs/scripts/samba-masquerade.sh
```

## [`service-event.sh`](/scripts/service-event.sh)

This script tries to emulate [service-event script from Merlin firmware](https://github.com/RMerl/asuswrt-merlin.ng/wiki/User-scripts#service-event-end) but there is no guarantee whenever it will run before or after the event. [Example custom script](/examples/service-script.sh) that can be used with this script.

By default, integrates with all scripts (when required) present in this repository.

```sh
curl -fsSL "https://raw.githubusercontent.com/jacklul/asuswrt-scripts/master/scripts/service-event.sh" -o /jffs/scripts/service-event.sh
```

## [`swap.sh`](/scripts/swap.sh)

This script enables swap file on start, with configurable size and location.

```sh
curl -fsSL "https://raw.githubusercontent.com/jacklul/asuswrt-scripts/master/scripts/swap.sh" -o /jffs/scripts/swap.sh
```

## [`temperature-warning.sh`](/scripts/temperature-warning.sh)

This script will send log message when CPU or WLAN chip temperatures reach specified threshold.

Be default, the treshold is set to 80C.

```sh
curl -fsSL "https://raw.githubusercontent.com/jacklul/asuswrt-scripts/master/scripts/temperature-warning.sh" -o /jffs/scripts/temperature-warning.sh
```

## [`update-notify.sh`](/scripts/update-notify.sh)

This script will send you a Telegram message when new router firmware is available.

You need to create a Telegram bot for this to work.

```sh
curl -fsSL "https://raw.githubusercontent.com/jacklul/asuswrt-scripts/master/scripts/update-notify.sh" -o /jffs/scripts/update-notify.sh
```

## [`update-scripts.sh`](/scripts/update-scripts.sh)

This script updates all `*.sh` scripts present in the `/jffs/scripts` folder.

This is on-demand script that must be ran manually.

```sh
curl -fsSL "https://raw.githubusercontent.com/jacklul/asuswrt-scripts/master/scripts/update-scripts.sh" -o /jffs/scripts/update-scripts.sh
```

## [`usb-mount.sh`](/scripts/usb-mount.sh)

This script will mount any USB storage device in `/tmp/mnt` directory if for some reason the official firmware does not automount it for you.

Recommended to use [`hotplug-event.sh`](#user-content-hotplug-eventsh) as well.

```sh
curl -fsSL "https://raw.githubusercontent.com/jacklul/asuswrt-scripts/master/scripts/usb-mount.sh" -o /jffs/scripts/usb-mount.sh
```

## [`usb-network.sh`](/scripts/usb-network.sh)

This script will add any USB networking gadget to LAN bridge interface, making it member of your LAN network.

This is a great way of running Pi-hole in your network on a [Raspberry Pi Zero connected through USB port](https://github.com/jacklul/asuswrt-usb-raspberry-pi).

Recommended to use [`service-event.sh`](#user-content-service-eventsh) and [`hotplug-event.sh`](#user-content-hotplug-eventsh) as well.

```sh
curl -fsSL "https://raw.githubusercontent.com/jacklul/asuswrt-scripts/master/scripts/usb-network.sh" -o /jffs/scripts/usb-network.sh
```

## [`vpn-killswitch.sh`](/scripts/vpn-killswitch.sh)

This script will prevent your LAN from accessing the internet through the WAN interface.

There might be a small window after router boots and before this script runs when you can connect through the WAN interface but there is no way to avoid this on stock firmware.

Recommended to use [`service-event.sh`](#user-content-service-eventsh) as well.

```sh
curl -fsSL "https://raw.githubusercontent.com/jacklul/asuswrt-scripts/master/scripts/vpn-killswitch.sh" -o /jffs/scripts/vpn-killswitch.sh
```

## [`wgs-lanonly.sh`](/scripts/wgs-lanonly.sh)

This script will prevent clients connected to WireGuard server from accessing the internet.

Recommended to use [`service-event.sh`](#user-content-service-eventsh) as well.

```sh
curl -fsSL "https://raw.githubusercontent.com/jacklul/asuswrt-scripts/master/scripts/wgs-lanonly.sh" -o /jffs/scripts/wgs-lanonly.sh
```
