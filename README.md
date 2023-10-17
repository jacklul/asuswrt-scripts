# Custom scripts for AsusWRT

This uses known `script_usbmount` NVRAM variable to run "startup" script on USB mount event that starts things out.

Obviously this requires some kind of USB storage plugged into the router for this to work, you don't need it on Asuswrt-Merlin though - just start the scripts from [services-start script](https://github.com/RMerl/asuswrt-merlin.ng/wiki/User-scripts#services-start).

Everything here was tested on **RT-AX58U v2** on official **388.2** firmware (**3.0.0.4.388.22525** to be precise), there is no guarantee that everything will work on non-AX routers and on lower firmware versions.

**Some routers are no longer executing commands from `script_usbmount` NVRAM variable on USB mount - in that case [look here](/asusware-usbmount) for a workaround.**

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

If there is another file with the same base name as the script then it is required for that script to work.

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

## [`disable-wps.sh`](/scripts/disable-wps.sh)

This script does exactly what you would expect - makes sure WPS stays disabled.

By default, runs check at boot and at 00:00.

```sh
curl -fsSL "https://raw.githubusercontent.com/jacklul/asuswrt-scripts/master/scripts/disable-wps.sh" -o /jffs/scripts/disable-wps.sh
```

## [`dynamic-dns.sh`](/scripts/dynamic-dns.sh)

This script implements [custom DDNS feature from Merlin firmware](https://github.com/RMerl/asuswrt-merlin.ng/wiki/DDNS-services#using-one-of-the-services-supported-by-in-a-dyn-but-not-by-the-asuswrt-merlin-webui) that allows you to use custom [Inadyn](https://github.com/troglobit/inadyn) config file.

Checks every minute for new IP in NVRAM variable `wan0_ipaddr`. You can alternatively configure it to use website API like "[ipecho.net/plain](https://ipecho.net/plain)".

Recommended to use [`service-event.sh`](#user-content-service-eventsh) as well.

```sh
curl -fsSL "https://raw.githubusercontent.com/jacklul/asuswrt-scripts/master/scripts/dynamic-dns.sh" -o /jffs/scripts/dynamic-dns.sh
```

## [`force-dns.sh`](/scripts/force-dns.sh)

This script will force specified DNS server to be used by LAN and Guest WiFi, can also prevent clients from querying the router's DNS server.

This script can be very useful when running Pi-hole in your LAN.

Recommended to use [`service-event.sh`](#user-content-service-eventsh) as well.

```sh
curl -fsSL "https://raw.githubusercontent.com/jacklul/asuswrt-scripts/master/scripts/force-dns.sh" -o /jffs/scripts/force-dns.sh
```

## [`guest-password.sh`](/scripts/guest-password.sh)

This script rotates Guest WiFi passwords for specified guest networks and/or generates HTML pages with QR code to let your guests connect easily. ([HTML page screenshot](/.assets/guest-password.png))

HTML pages will be accessible under these URLS:
- www.asusrouter.com/user/guest-list.html
- www.asusrouter.com/user/guest-NETWORK.html

Recommended to use [`service-event.sh`](#user-content-service-eventsh) as well.

```sh
curl -fsSL "https://raw.githubusercontent.com/jacklul/asuswrt-scripts/master/scripts/guest-password.sh" -o /jffs/scripts/guest-password.sh
curl -fsSL "https://raw.githubusercontent.com/jacklul/asuswrt-scripts/master/scripts/guest-password.html" -o /jffs/scripts/guest-password.html
```

## [`led-control.sh`](/scripts/led-control.sh)

**Warning: this script is not complete and will probably not work on stock firmware (should work on Merlin), see note in the script.**

This script implements [scheduled LED control](https://github.com/RMerl/asuswrt-merlin.ng/wiki/Scheduled-LED-control).

By default, LEDs shutdown at 00:00 and turn on at 06:00.

```sh
curl -fsSL "https://raw.githubusercontent.com/jacklul/asuswrt-scripts/master/scripts/led-control.sh" -o /jffs/scripts/led-control.sh
```

## [`process-killer.sh`](/scripts/process-killer.sh)

This script can kill processes by their names, unfortunately on stock most of them will restart, there is an attempt to prevent that in that script but it is not guaranteed to work.

```sh
curl -fsSL "https://raw.githubusercontent.com/jacklul/asuswrt-scripts/master/scripts/process-killer.sh" -o /jffs/scripts/process-killer.sh
```

## [`rclone-backup.sh`](/scripts/rclone-backup.sh)

This script can backup all NVRAM variables and selected `/jffs` contents to cloud service using [Rclone](https://github.com/rclone/rclone).

You should probably store the binary on USB drive but the script has also an option to automatically download the binary before running then deleting it afterwards. Make sure your device has enough memory for this though.

```sh
curl -fsSL "https://raw.githubusercontent.com/jacklul/asuswrt-scripts/master/scripts/rclone-backup.sh" -o /jffs/scripts/rclone-backup.sh
curl -fsSL "https://raw.githubusercontent.com/jacklul/asuswrt-scripts/master/scripts/rclone-backup.list" -o /jffs/scripts/rclone-backup.list
```

## [`samba-masquerade.sh`](/scripts/samba-masquerade.sh)

Enables masquerade for Samba ports to allow VPN clients to connect to your LAN shares.

By default, default networks for WireGuard, OpenVPN and IPSec are set.

Recommended to use [`service-event.sh`](#user-content-service-eventsh) as well.

```sh
curl -fsSL "https://raw.githubusercontent.com/jacklul/asuswrt-scripts/master/scripts/samba-masquerade.sh" -o /jffs/scripts/samba-masquerade.sh
```

## [`service-event.sh`](/scripts/service-event.sh)

This script tries to emulate [service-event script from Merlin firmware](https://github.com/RMerl/asuswrt-merlin.ng/wiki/User-scripts#service-event-end) but there is no guarantee whenever it will run before or after the event.

By default, integrates with all scripts present in this repository.

```sh
curl -fsSL "https://raw.githubusercontent.com/jacklul/asuswrt-scripts/master/scripts/service-event.sh" -o /jffs/scripts/service-event.sh
```

## [`swap.sh`](/scripts/swap.sh)

**Warning: this script will probably not work on stock firmware (should work on Merlin), see note in the script.**

This script enables swap file on start, with configurable size and location.

```sh
curl -fsSL "https://raw.githubusercontent.com/jacklul/asuswrt-scripts/master/scripts/swap.sh" -o /jffs/scripts/swap.sh
```

## [`tailscale.sh`](/scripts/tailscale.sh)

This script installs [Tailscale](https://tailscale.com) service on your router, allowing it to be used as an exit node.

You should probably store the binaries on USB drive but the script has also an option to automatically download the binaries. Make sure your device has enough memory for this though.

Recommended to use [`service-event.sh`](#user-content-service-eventsh) as well.

```sh
curl -fsSL "https://raw.githubusercontent.com/jacklul/asuswrt-scripts/master/scripts/tailscale.sh" -o /jffs/scripts/tailscale.sh
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

This script updates all `*.sh` scripts present in the `/jffs/scripts` folder (also including their extra files).

This is on-demand script that must be ran manually.

```sh
curl -fsSL "https://raw.githubusercontent.com/jacklul/asuswrt-scripts/master/scripts/update-scripts.sh" -o /jffs/scripts/update-scripts.sh
```

## [`usb-network.sh`](/scripts/usb-network.sh)

This script will add any USB networking gadget to LAN bridge interface, making it member of your LAN network.

This is a great way of running Pi-hole in your network on a [Raspberry Pi Zero connected through USB port](https://github.com/jacklul/asuswrt-usb-raspberry-pi).

Recommended to use [`service-event.sh`](#user-content-service-eventsh) as well.

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
