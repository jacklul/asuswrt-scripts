# Custom scripts for AsusWRT

This uses known `script_usbmount` NVRAM variable to run "startup" script on USB mount event that starts things out.

Obviously this requires some kind of USB storage plugged into the router for this to work, you don't need it on Asuswrt-Merlin though - just start the scripts from [services-start script](https://github.com/RMerl/asuswrt-merlin.ng/wiki/User-scripts#services-start).

**If your router is not executing commands from `script_usbmount` NVRAM variable on USB mount - [look here](/asusware-usbmount) for a workaround.**

Everything here was tested on **RT-AX58U v2** on official **388.2** firmware (**3.0.0.4.388.22525** to be precise), there is no guarantee that everything will work on non-AX routers and on lower firmware ones. Some informations were pulled from **GPL_RT-AX58U_3.0.0.4.388.22525-gd35b8fe** sources.

**A lot of scripts here are based on resources from [SNBForums](https://www.snbforums.com) and [asuswrt-merlin.ng wiki](https://github.com/RMerl/asuswrt-merlin.ng/wiki), big thanks to everyone who made those contributions to the community.**

## Installation

Install startup script:

```bash
curl -fsSL "https://raw.githubusercontent.com/jacklul/asuswrt-scripts/master/scripts-startup.sh" -o /jffs/scripts-startup.sh
/bin/sh /jffs/scripts-startup.sh install
```

_If you would like for it to be called differently you can rename it (you can also place it different path if you wish)._

Install scripts you want to use from [section below](#available-scripts).

# Available scripts

<table>
<tr>
<td>
<a href="#user-content-conditional-rebootsh">conditional-reboot</a><br>
<a href="#user-content-cron-queuesh">cron-queue</a><br>
<a href="#user-content-custom-configssh">custom-configs</a><br>
<a href="#user-content-disable-diagsh">disable-diag</a><br>
<a href="#user-content-disable-wpssh">disable-wps</a><br>
<a href="#user-content-dynamic-dnssh">dynamic-dns</a><br>
<a href="#user-content-entwaresh">entware</a><br>
<a href="#user-content-force-dnssh">force-dns</a><br>
<a href="#user-content-guest-passwordsh">guest-password</a><br>
</td>
<td>
<a href="#user-content-hotplug-eventsh">hotplug-event</a><br>
<a href="#user-content-led-controlsh">led-control</a><br>
<a href="#user-content-modify-featuressh">modify-features</a><br>
<a href="#user-content-modify-webuish">modify-webui</a><br>
<a href="#user-content-netboot-downloadsh">netboot-download</a><br>
<a href="#user-content-process-killersh">process-killer</a><br>
<a href="#user-content-rclone-backupsh">rclone-backup</a><br>
<a href="#user-content-samba-masqueradesh">samba-masquerade</a><br>
<a href="#user-content-service-eventsh">service-event</a><br>
</td>
<td>
<a href="#user-content-swapsh">swap</a><br>
<a href="#user-content-temperature-warningsh">temperature-warning</a><br>
<a href="#user-content-update-notifysh">update-notify</a><br>
<a href="#user-content-update-scriptssh">update-scripts</a><br>
<a href="#user-content-usb-mountsh">usb-mount</a><br>
<a href="#user-content-usb-networksh">usb-network</a><br>
<a href="#user-content-vpn-killswitchsh">vpn-killswitch</a><br>
<a href="#user-content-wgs-lanonlysh">wgs-lanonly</a><br>
</td>
</tr>
</table>

You can override config variables for scripts by creating `.conf` with the same base name as the script (for example: `conditional-reboot.conf`).

Remember to mark the scripts as executable after installing, you can do it in one command like this:
```sh
chmod +x /jffs/scripts/*.sh
```

---

## [`conditional-reboot.sh`](/scripts/conditional-reboot.sh)

This script will reboot your router at specified time if it's been running for fixed amount of time.

By default, reboot happens at <ins>5AM when uptime exceeds 7 days</ins>.

```sh
curl -fsSL "https://raw.githubusercontent.com/jacklul/asuswrt-scripts/master/scripts/conditional-reboot.sh" -o /jffs/scripts/conditional-reboot.sh
```

<a href="#available-scripts"><i> ^ back to the list ^ </i></a><br>

## [`cron-queue.sh`](/scripts/cron-queue.sh)

When running multiple scripts from this repository that run every minute via cron they can cause a CPU spike (and ping spike on some devices).
This script will run all "every minute" tasks synchronously which will reduce the CPU load in exchange for task execution delays.

All scripts from this repository integrate with this script and will use it instead of `cru` when it's available.

```sh
curl -fsSL "https://raw.githubusercontent.com/jacklul/asuswrt-scripts/master/scripts/cron-queue.sh" -o /jffs/scripts/cron-queue.sh
```

<a href="#available-scripts"><i> ^ back to the list ^ </i></a><br>

## [`custom-configs.sh`](/scripts/custom-configs.sh)

This script implements [Custom config files from Merlin firmware](https://github.com/RMerl/asuswrt-merlin.ng/wiki/Custom-config-files) that allows you to use custom config files for certain services.

**Supported config files:**
- profile (profile.add only)
- hosts
- avahi-daemon.conf
- dnsmasq.conf
- minidlna.conf
- mt-daapd.conf
- smb.conf
- vsftpd.conf

**Supported postconf scripts:**
- hosts.postconf
- avahi-daemon.postconf
- dnsmasq.postconf
- minidlna.postconf
- mt-daapd.postconf
- smb.postconf
- vsftpd.postconf

**Keep in mind that for **postconf scripts** you have to reference `.new` in the file name instead (for example `/etc/smb.conf.new`), the correct file path will be passed as an argument to the script.**

_NOTE: Usage of Samba, FTP and Media services without any USB storage requires `nvram set usb_debug=1`._

_Recommended to use [`service-event.sh`](#user-content-service-eventsh) as well._

```sh
curl -fsSL "https://raw.githubusercontent.com/jacklul/asuswrt-scripts/master/scripts/custom-configs.sh" -o /jffs/scripts/custom-configs.sh
```

<a href="#available-scripts"><i> ^ back to the list ^ </i></a><br>

## [`disable-diag.sh`](/scripts/disable-diag.sh)

This script prevent `conn_diag` from (re)starting `amas_portstatus` which likes to hog the CPU.

No idea what `conn_diag` is itself, some kind of diagnostics utility.

```sh
curl -fsSL "https://raw.githubusercontent.com/jacklul/asuswrt-scripts/master/scripts/disable-diag.sh" -o /jffs/scripts/disable-diag.sh
```

<a href="#available-scripts"><i> ^ back to the list ^ </i></a><br>

## [`disable-wps.sh`](/scripts/disable-wps.sh)

This script does exactly what you would expect - makes sure WPS stays disabled.

By default, runs check <ins>at boot and at 00:00</ins>, when `service-event.sh` is used also <ins>runs every time wireless is restarted</ins>.

_Recommended to use [`service-event.sh`](#user-content-service-eventsh) as well._

```sh
curl -fsSL "https://raw.githubusercontent.com/jacklul/asuswrt-scripts/master/scripts/disable-wps.sh" -o /jffs/scripts/disable-wps.sh
```

<a href="#available-scripts"><i> ^ back to the list ^ </i></a><br>

## [`dynamic-dns.sh`](/scripts/dynamic-dns.sh)

This script implements [custom DDNS feature from Merlin firmware](https://github.com/RMerl/asuswrt-merlin.ng/wiki/DDNS-services#using-one-of-the-services-supported-by-in-a-dyn-but-not-by-the-asuswrt-merlin-webui) that allows you to use custom [Inadyn](https://github.com/troglobit/inadyn) config file.

Checks <ins>every minute</ins> for new IP in NVRAM variable `wan0_ipaddr`. You can alternatively configure it to use website API like "[ipecho.net/plain](https://ipecho.net/plain)".

On Merlin firmware you should call this script from `ddns-start` with `force` argument instead of `start`.

**You might have to install Entware's `curl` to bypass the limitations of the firmware one.**

_Recommended to use [`service-event.sh`](#user-content-service-eventsh) as well._

```sh
curl -fsSL "https://raw.githubusercontent.com/jacklul/asuswrt-scripts/master/scripts/dynamic-dns.sh" -o /jffs/scripts/dynamic-dns.sh
```

<a href="#available-scripts"><i> ^ back to the list ^ </i></a><br>

## [`entware.sh`](/scripts/entware.sh)

This script installs and enables [Entware](https://github.com/Entware/Entware), even in RAM (`/tmp`).

When installing to `/tmp` it will automatically install specified packages and symlink files from `/jffs/entware` to `/opt`. If you want to symlink whole directory then create `.symlinkthisdir` file in its root, be careful to not nest those and not symlink important directories like `/opt/etc`.

**If you want to use HTTPS to download packages you might have to install Entware's `wget-ssl` and `ca-certificates`.**

_Recommended to use [`hotplug-event.sh`](#user-content-hotplug-eventsh) as well._

```sh
curl -fsSL "https://raw.githubusercontent.com/jacklul/asuswrt-scripts/master/scripts/entware.sh" -o /jffs/scripts/entware.sh
```

<a href="#available-scripts"><i> ^ back to the list ^ </i></a><br>

## [`force-dns.sh`](/scripts/force-dns.sh)

This script will force specified DNS server to be used by LAN and Guest WiFi, can also prevent clients from querying the router's DNS server.

This script can be very useful when running [Pi-hole](https://pi-hole.net) in your LAN.

_Recommended to use [`service-event.sh`](#user-content-service-eventsh) as well._

```sh
curl -fsSL "https://raw.githubusercontent.com/jacklul/asuswrt-scripts/master/scripts/force-dns.sh" -o /jffs/scripts/force-dns.sh
```

<a href="#available-scripts"><i> ^ back to the list ^ </i></a><br>

## [`guest-password.sh`](/scripts/guest-password.sh)

This script rotates **Guest WiFi** passwords.

By default, it rotates passwords for the first network pair at <ins>4AM</ins>.

```sh
curl -fsSL "https://raw.githubusercontent.com/jacklul/asuswrt-scripts/master/scripts/guest-password.sh" -o /jffs/scripts/guest-password.sh
```

<a href="#available-scripts"><i> ^ back to the list ^ </i></a><br>

## [`hotplug-event.sh`](/scripts/hotplug-event.sh)

This script handles hotplug events.

By default, integrates with all scripts present in this repository.

```sh
curl -fsSL "https://raw.githubusercontent.com/jacklul/asuswrt-scripts/master/scripts/hotplug-event.sh" -o /jffs/scripts/hotplug-event.sh
```

<a href="#available-scripts"><i> ^ back to the list ^ </i></a><br>

## [`led-control.sh`](/scripts/led-control.sh)

**Warning: this script is not complete and will probably not work on stock firmware (should work on Merlin), see note in the script.**

This script implements [scheduled LED control from Merlin firmware](https://github.com/RMerl/asuswrt-merlin.ng/wiki/Scheduled-LED-control).

By default, LEDs shutdown at <ins>00:00 and turn on at 06:00</ins>.

```sh
curl -fsSL "https://raw.githubusercontent.com/jacklul/asuswrt-scripts/master/scripts/led-control.sh" -o /jffs/scripts/led-control.sh
```

<a href="#available-scripts"><i> ^ back to the list ^ </i></a><br>

## [`modify-features.sh`](/scripts/modify-features.sh)

This script modifies `rc_support` NVRAM variable to enable/disable some features, this is mainly for hiding Web UI menus and tabs.

A good place to look for potential values are `init.c` and `state.js` files in the firmware sources.

_Recommended to use [`service-event.sh`](#user-content-service-eventsh) as well._

```sh
curl -fsSL "https://raw.githubusercontent.com/jacklul/asuswrt-scripts/master/scripts/modify-features.sh" -o /jffs/scripts/modify-features.sh
```

<a href="#available-scripts"><i> ^ back to the list ^ </i></a><br>

## [`modify-webui.sh`](/scripts/modify-webui.sh)

This script modifies some web UI elements.

**Currently applied modifications:**
- display CPU temperature on the system status screen (with realtime updates)
- show connect QR code on guest network edit screen and hide the passwords on the main screen
- add `notrendmicro` rc_support option that hides all Trend Micro services, **Speed Test** will be moved to **Network Tools** menu (to be used with [`modify-features.sh`](#user-content-modify-featuressh))

```sh
curl -fsSL "https://raw.githubusercontent.com/jacklul/asuswrt-scripts/master/scripts/modify-webui.sh" -o /jffs/scripts/modify-webui.sh
```

<a href="#available-scripts"><i> ^ back to the list ^ </i></a><br>

## [`netboot-download.sh`](/scripts/netboot-download.sh)

Automatically download specified bootloader files from [netboot.xyz](https://netboot.xyz).

This and [`custom-configs.sh`](#user-content-custom-configssh) can help you setup a **netboot.xyz** PXE server on the router.

**You might have to install Entware's `curl` to bypass the limitations of the firmware one.**

```sh
curl -fsSL "https://raw.githubusercontent.com/jacklul/asuswrt-scripts/master/scripts/netboot-download.sh" -o /jffs/scripts/netboot-download.sh
```

<a href="#available-scripts"><i> ^ back to the list ^ </i></a><br>

## [`process-killer.sh`](/scripts/process-killer.sh)

This script can kill processes by their names, unfortunately on stock most of them will restart, there is an attempt to prevent that in that script but it is not guaranteed to work.

**Use this script at your own risk.**

```sh
curl -fsSL "https://raw.githubusercontent.com/jacklul/asuswrt-scripts/master/scripts/process-killer.sh" -o /jffs/scripts/process-killer.sh
```

<a href="#available-scripts"><i> ^ back to the list ^ </i></a><br>

## [`rclone-backup.sh`](/scripts/rclone-backup.sh)

This script can backup all NVRAM variables and selected `/jffs` contents to cloud service using [Rclone](https://github.com/rclone/rclone).

You have to download the binary and place it on the USB drive. If you installed it through the **Entware** then it will be automatically detected, alternatively it will install it when it detects **Entware** installation (then remove it after the job is done - this feature is targeted for installation in `/tmp`).

**If automatic installation of `rclone` fails then you might have to install Entware's `wget` (or `wget-ssl` when using HTTPS) to bypass the limitations of the firmware one.**

[Example backup list](/extras/rclone.list) that can be used with this script.

```sh
curl -fsSL "https://raw.githubusercontent.com/jacklul/asuswrt-scripts/master/scripts/rclone-backup.sh" -o /jffs/scripts/rclone-backup.sh
```

<a href="#available-scripts"><i> ^ back to the list ^ </i></a><br>

## [`samba-masquerade.sh`](/scripts/samba-masquerade.sh)

Enables masquerading for Samba ports to allow VPN clients to connect to your LAN shares.

By default, default networks for WireGuard, OpenVPN and IPSec are allowed.

_Recommended to use [`service-event.sh`](#user-content-service-eventsh) as well._

```sh
curl -fsSL "https://raw.githubusercontent.com/jacklul/asuswrt-scripts/master/scripts/samba-masquerade.sh" -o /jffs/scripts/samba-masquerade.sh
```

<a href="#available-scripts"><i> ^ back to the list ^ </i></a><br>

## [`service-event.sh`](/scripts/service-event.sh)

This script tries to emulate [service-event script from Merlin firmware](https://github.com/RMerl/asuswrt-merlin.ng/wiki/User-scripts#service-event-end) but there is no guarantee whenever it will run before or after the event. [Example custom script](/extras/service-script.sh) that can be used with this script.

By default, integrates with all scripts (when required) present in this repository.

```sh
curl -fsSL "https://raw.githubusercontent.com/jacklul/asuswrt-scripts/master/scripts/service-event.sh" -o /jffs/scripts/service-event.sh
```

<a href="#available-scripts"><i> ^ back to the list ^ </i></a><br>

## [`swap.sh`](/scripts/swap.sh)

This script enables swap file on start, with configurable size and location.

```sh
curl -fsSL "https://raw.githubusercontent.com/jacklul/asuswrt-scripts/master/scripts/swap.sh" -o /jffs/scripts/swap.sh
```

<a href="#available-scripts"><i> ^ back to the list ^ </i></a><br>

## [`temperature-warning.sh`](/scripts/temperature-warning.sh)

This script will send log message when CPU or WLAN chip temperatures reach specified threshold.

Be default, the treshold is set to <ins>80C</ins>.

```sh
curl -fsSL "https://raw.githubusercontent.com/jacklul/asuswrt-scripts/master/scripts/temperature-warning.sh" -o /jffs/scripts/temperature-warning.sh
```

<a href="#available-scripts"><i> ^ back to the list ^ </i></a><br>

## [`update-notify.sh`](/scripts/update-notify.sh)

This script will send you a notification when new router firmware is available.

**Currently supported notification providers:**
- Email
- [Telegram](https://telegram.org)
- [Pushover](https://pushover.net)
- [Pushbullet](https://www.pushbullet.com)

**You might have to install Entware's `curl` to bypass the limitations of the firmware one.**

_You can test the notifications by using `update-notify.sh test` (if it works from the cron) and `update-notify.sh test now` (if it actually sends) commands._

```sh
curl -fsSL "https://raw.githubusercontent.com/jacklul/asuswrt-scripts/master/scripts/update-notify.sh" -o /jffs/scripts/update-notify.sh
```

<a href="#available-scripts"><i> ^ back to the list ^ </i></a><br>

## [`update-scripts.sh`](/scripts/update-scripts.sh)

This script updates all `*.sh` scripts present in the `/jffs/scripts` folder.

This is on-demand script that must be ran manually.

```sh
curl -fsSL "https://raw.githubusercontent.com/jacklul/asuswrt-scripts/master/scripts/update-scripts.sh" -o /jffs/scripts/update-scripts.sh
```

<a href="#available-scripts"><i> ^ back to the list ^ </i></a><br>

## [`usb-mount.sh`](/scripts/usb-mount.sh)

This script will mount any USB storage device in `/tmp/mnt` directory if for some reason the official firmware does not automount it for you.

_Recommended to use [`hotplug-event.sh`](#user-content-hotplug-eventsh) as well._

```sh
curl -fsSL "https://raw.githubusercontent.com/jacklul/asuswrt-scripts/master/scripts/usb-mount.sh" -o /jffs/scripts/usb-mount.sh
```

<a href="#available-scripts"><i> ^ back to the list ^ </i></a><br>

## [`usb-network.sh`](/scripts/usb-network.sh)

This script will add any USB networking gadget to LAN bridge interface, making it member of your LAN network.

This is a great way of running Pi-hole in your network on a [Raspberry Pi Zero connected through USB port](https://github.com/jacklul/asuswrt-usb-raspberry-pi).

_Recommended to use [`service-event.sh`](#user-content-service-eventsh) and [`hotplug-event.sh`](#user-content-hotplug-eventsh) as well._

```sh
curl -fsSL "https://raw.githubusercontent.com/jacklul/asuswrt-scripts/master/scripts/usb-network.sh" -o /jffs/scripts/usb-network.sh
```

<a href="#available-scripts"><i> ^ back to the list ^ </i></a><br>

## [`vpn-killswitch.sh`](/scripts/vpn-killswitch.sh)

This script will prevent your LAN from accessing the internet through the WAN interface.

There might be a small window after router boots and before this script runs when you can connect through the WAN interface but there is no way to avoid this on stock firmware.

_Recommended to use [`service-event.sh`](#user-content-service-eventsh) as well._

```sh
curl -fsSL "https://raw.githubusercontent.com/jacklul/asuswrt-scripts/master/scripts/vpn-killswitch.sh" -o /jffs/scripts/vpn-killswitch.sh
```

<a href="#available-scripts"><i> ^ back to the list ^ </i></a><br>

## [`wgs-lanonly.sh`](/scripts/wgs-lanonly.sh)

This script will prevent clients connected to WireGuard server from accessing the internet.

_Recommended to use [`service-event.sh`](#user-content-service-eventsh) as well._

```sh
curl -fsSL "https://raw.githubusercontent.com/jacklul/asuswrt-scripts/master/scripts/wgs-lanonly.sh" -o /jffs/scripts/wgs-lanonly.sh
```
