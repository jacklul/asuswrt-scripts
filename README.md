# Custom scripts for stock ASUS routers

This is a collection of custom scripts for ASUS routers running stock firmware that will enhance your router's functionality.

> [!NOTE]
> On **2025-09-05** this project went through an overhaul to make the installation and usage easier!  
> New main script can migrate the old scripts but starting fresh is recommended!

Most of the scripts were tested on **RT-AX58U v2** running recent official firmware - I give no guarantee that everything will work on other routers or older firmware versions.  
Some informations were pulled from **GPL_RT-AX58U_3.0.0.4.388.22525** sources as well as [RMerl/asuswrt-merlin.ng](https://github.com/RMerl/asuswrt-merlin.ng) repository.

**A lot of scripts here are based on resources from [SNBForums](https://www.snbforums.com), [asuswrt-merlin.ng wiki](https://github.com/RMerl/asuswrt-merlin.ng/wiki) or other sources.  
Scripts based on an existing resource have it linked in the header.**

## Installation

> [!IMPORTANT]
> You need a router with USB port (and **ASUS Download Master** support) when using official firmware to be able to start the scripts.
> This is not required on Asuswrt-Merlin as you can use [services-start](https://github.com/RMerl/asuswrt-merlin.ng/wiki/User-scripts#services-start) script.

> [!WARNING]
> Newer versions of the official firmware have blocked the ability to start scripts using `script_usbmount` NVRAM variable and require a [workaround](/asusware-usb-mount-script) to be applied first.
>
> <details>
> <summary>Instructions to check if your router is affected</summary>
>
> - SSH into the router
> - Run `nvram set script_usbmount="/bin/touch /tmp/yesitworks"`
> - Wait around 15 seconds then execute `nvram get script_usbmount` - **if there is no output then your router is affected**
> - Plug in any USB storage - make sure the router mounts it as storage (needs supported filesystem)
> - Run `cat /tmp/yesitworks` - **if you see `No such file or directory` message then your router is affected**
> 
> Make sure to reset the variable to empty value if your router is not affected - `nvram set script_usbmount=`
>
> </details>

Run this simple installer to install the main script (`jas.sh`):

```sh
curl "https://raw.githubusercontent.com/jacklul/asuswrt-scripts/master/install.sh" | sh
```

<details>
<summary>curl is not available? try wget</summary>

```sh
wget "https://raw.githubusercontent.com/jacklul/asuswrt-scripts/master/install.sh" -O - | sh
```

</details>

Then you can proceed to install scripts you want to use:

```sh
/jffs/scripts/jas.sh install <name>
# passing multiple is also supported:
# /jffs/scripts/jas.sh install cron-queue custom-configs entware
```

**See below for [list of available scripts](#available-scripts).**

Start everything up after you're done installing and configuring the scripts:

```sh
/jffs/scripts/jas.sh start
# or start individual scripts like this:
/jffs/scripts/jas.sh custom-configs start
```

## Available scripts

<table>
<tr>
<td>
<a href="#user-content-cron-queue">cron-queue</a><br>
<a href="#user-content-custom-configs">custom-configs</a><br>
<a href="#user-content-disable-wps">disable-wps</a><br>
<a href="#user-content-dynamic-dns">dynamic-dns</a><br>
<a href="#user-content-entware">entware</a><br>
<a href="#user-content-extra-ip">extra-ip</a><br>
<a href="#user-content-force-dns">force-dns</a><br>
<a href="#user-content-fstrim">fstrim</a><br>
<a href="#user-content-guest-password">guest-password</a><br>
<a href="#user-content-hotplug-event">hotplug-event</a><br>
</td>
<td>
<a href="#user-content-led-control">led-control</a><br>
<a href="#user-content-modify-features">modify-features</a><br>
<a href="#user-content-modify-webui">modify-webui</a><br>
<a href="#user-content-process-affinity">process-affinity</a><br>
<a href="#user-content-process-killer">process-killer</a><br>
<a href="#user-content-rclone-backup">rclone-backup</a><br>
<a href="#user-content-service-event">service-event</a><br>
<a href="#user-content-swap">swap</a><br>
<a href="#user-content-temperature-warning">temperature-warning</a><br>
<a href="#user-content-update-notify">update-notify</a><br>
</td>
<td>
<a href="#user-content-uptime-reboot">uptime-reboot</a><br>
<a href="#user-content-usb-network">usb-network</a><br>
<a href="#user-content-vpn-firewall">vpn-firewall</a><br>
<a href="#user-content-vpn-ip-routes">vpn-ip-routes</a><br>
<a href="#user-content-vpn-kill-switch">vpn-kill-switch</a><br>
<a href="#user-content-vpn-monitor">vpn-monitor</a><br>
<a href="#user-content-vpn-samba">vpn-samba</a><br>
<a href="#user-content-vpn-vserver">vpn-vserver</a><br>
<a href="#user-content-wgs-lan-only">wgs-lan-only</a><br>
</td>
</tr>
</table>

> [!TIP]
> You can override a script's configuration variables by creating `.conf` with the same name (for example: `uptime-reboot.conf`).  
> Configuration variables are defined on top of each script - peek into the script to see what is available to change!  
> You can also use `/jffs/scripts/jas.sh config <name>` command to open configuration file using available text editor (`$EDITOR`).  
> **Please note that most scripts do not validate values at all, it is your responsibility to make sure that the values you set are correct.**

---

## [`cron-queue`](/scripts/cron-queue.sh)

When running multiple scripts from this repository that run every minute via cron they can cause a CPU spike (and network wide ping spike on weaker devices).  
This script will run all "every minute" tasks sequentially which will reduce the CPU load in exchange for execution delays.

All scripts from this repository integrate with this script and will use it instead of `cru` command when it's available.  
It is recommended to use this script if you install multiple scripts that must run every minute (check `cru l` and look for `*/1 * * * *` entries).

---

## [`custom-configs`](/scripts/custom-configs.sh)

This script implements [custom config files from Asuswrt-Merlin firmware](https://github.com/RMerl/asuswrt-merlin.ng/wiki/Custom-config-files) that allows you to edit config files for certain build-in services.  
**Unfortunately not every modification will be possible as the services have to start first then be restarted by the script to modify the configs.**

<details>
<summary>Supported config files</summary>

<br>

- avahi-daemon.conf
- dnsmasq.conf
- hosts
- igmpproxy.conf *
- ipsec.conf *
- mcpd.conf *
- minidlna.conf
- mt-daapd.conf
- pptpd.conf *
- profile (profile.add only)
- resolv.conf
- ripd.conf *
- smb.conf
- snmpd.conf *
- stubby.yml (stubby.yml.add only)
- torrc *
- vsftpd.conf
- upnp
- zebra.conf *

_* - Untested_

</details>

<details>
<summary>Supported postconf scripts</summary>

<br>

- avahi-daemon.postconf
- dnsmasq.postconf
- hosts.postconf
- igmpproxy.postconf *
- ipsec.postconf *
- mcpd.postconf *
- minidlna.postconf
- mt-daapd.postconf
- pptpd.postconf *
- resolv.postconf
- ripd.postconf *
- smb.postconf
- snmpd.postconf *
- stubby.postconf
- torrc.postconf *
- vsftpd.postconf
- upnp.postconf
- zebra.postconf *

_* - Untested_

</details>

> [!IMPORTANT]
> In **postconf scripts** you have to reference `.new` in the file name instead (for example `/etc/smb.conf.new`), the correct file path will be passed as an argument to the script (just like on Asuswrt-Merlin).

_Recommended to use [`service-event`](#user-content-service-event) as well for better reliability._

---

## [`disable-wps`](/scripts/disable-wps.sh)

This script makes sure WPS stays disabled.

By default, it runs at boot and at <ins>00:00 everyday</ins>.  
When `service-event.sh` is installed then it also <ins>runs every time wireless is restarted</ins>.

_Recommended to use [`service-event`](#user-content-service-event) as well for better reliability._

---

## [`dynamic-dns`](/scripts/dynamic-dns.sh)

This script implements [custom DDNS feature from Asuswrt-Merlin firmware](https://github.com/RMerl/asuswrt-merlin.ng/wiki/DDNS-services#using-one-of-the-services-supported-by-in-a-dyn-but-not-by-the-asuswrt-merlin-webui) that allows you to use custom [Inadyn](https://github.com/troglobit/inadyn) config file.

Script checks <ins>every minute</ins> for new IP in NVRAM variable `wan0_ipaddr`.  
You can alternatively configure it to use website API like "[ipecho.net/plain](https://ipecho.net/plain)".

> [!TIP]
> On Asuswrt-Merlin you should use `/jffs/scripts/ddns-start` instead.

> [!IMPORTANT]
> You might have to install Entware's `curl` (and `ca-bundle`) to bypass the security limitations of the one included in the stock firmware.

_Recommended to use [`service-event`](#user-content-service-event) as well for better reliability._

---

## [`entware`](/scripts/entware.sh)

This script launches [Entware](https://github.com/Entware/Entware) or installs it in RAM (`/tmp`) on start.

**This script does not install Entware automatically - run `./entware.sh install` manually.**

> [!TIP]
> When installing to RAM the script will automatically install specified packages from `IN_RAM` variable and symlink files from `/jffs/entware` to `/opt`.  
> Create `.symlinkthisdir` file in directory's root to symlink it directly or `.copythisdir` to copy it instead.  
> If you want a single file to be copied then create a file with the same name and `.copythisfile` extension, e.g. `file.txt.copythisfile`.

> [!IMPORTANT]
> If you want to use HTTPS to download packages you might have to install Entware's `wget-ssl` and `ca-bundle`.

_Recommended to use [`hotplug-event`](#user-content-hotplug-event) as well for better reliability._

---

## [`extra-ip`](/scripts/extra-ip.sh)

This script allows you to add an extra IP address(es) to a specific interface(s) (usually `br0`).  
This is mainly for running services on ports normally taken by the firmware (like a webserver).

> [!CAUTION]
> IPv6 support was not tested!

_Recommended to use [`service-event`](#user-content-service-event) as well for better reliability._

---

## [`force-dns`](/scripts/force-dns.sh)

This script will force specified DNS server to be used by LAN and Guest WiFi, can also prevent clients from querying the router's DNS server.

This script can be very useful when running [Pi-hole](https://pi-hole.net) in your network.

> [!TIP]
> On Asuswrt-Merlin you should use **DNS Director** instead.

> [!CAUTION]
> IPv6 support was not tested!

_Recommended to use [`service-event`](#user-content-service-event) as well for better reliability._

---

## [`fstrim`](/scripts/fstrim.sh)

> [!CAUTION]
> This script is currently untested.

This script will run `fstrim` command on a schedule for all mounted SSD devices.

By default, it runs at <ins>03:00 every Sunday</ins>.

_Recommended to use [`hotplug-event`](#user-content-hotplug-event) as well for better reliability._

---

## [`guest-password`](/scripts/guest-password.sh)

This script rotates **Guest WiFi** passwords to random strings.

By default, it rotates passwords for the first network pair at <ins>04:00 everyday</ins>.

---

## [`hotplug-event`](/scripts/hotplug-event.sh)

This script handles `block`, `net` and `misc` (`tun`, `tap`) hotplug events.

By default, integrates with all scripts present in this repository (where applicable).

---

## [`led-control`](/scripts/archive/led-control.sh)

> [!CAUTION]
> This script might not work with the official firmware very well as LED handling is different for almost every device.

This script implements [scheduled LED control from Asuswrt-Merlin firmware](https://github.com/RMerl/asuswrt-merlin.ng/wiki/Scheduled-LED-control).

By default, LEDs shutdown at <ins>00:00 and turn on at 06:00</ins>.

---

## [`modify-features`](/scripts/modify-features.sh)

This script modifies `rc_support` NVRAM variable to enable/disable some features, this is mainly for hiding Web UI menus and tabs.

A good place to look for potential values are `init.c` and `state.js` files in the firmware sources.

_Recommended to use [`service-event`](#user-content-service-event) as well for better reliability._

---

## [`modify-webui`](/scripts/modify-webui.sh)

This script modifies some web UI elements.

**Currently applied modifications:**

- display CPU temperature on the system status screen (with realtime updates)
- show connect QR code on guest network edit screen and hide the passwords on the main screen
- add `notrendmicro` rc_support option (to be used with [`modify-features`](#user-content-modify-features)) that hides all Trend Micro services, **Speed Test** will be moved to **Network Tools** menu
- allow use of port 443 for HTTPS LAN port in system settings

> [!NOTE]
> Tested only with English language!

> [!CAUTION]
> Compatibility with Asuswrt-Merlin is unknown!

---

## [`process-affinity`](/scripts/process-affinity.sh)

This script allows setting custom CPU affinity masks on processes.

If no mask is specified, it takes the affinity mask of `init` process and decreases its value by one, thus preventing the process from running on the first CPU core.

---

## [`process-killer`](/scripts/archive/process-killer.sh)

This script can kill processes by their names, unfortunately on the official firmware most of them will restart, there is an attempt to prevent that inside the script but it is not guaranteed to work.

> [!CAUTION]
> Use this script at your own risk.

---

## [`rclone-backup`](/scripts/rclone-backup.sh)

This script can backup all NVRAM variables and selected `/jffs` contents to cloud service using [Rclone](https://github.com/rclone/rclone).

By default, it runs at <ins>06:00 every Sunday</ins>.

You have to download the binary and place it on the USB drive.  
If you installed it through the **Entware** then it will be automatically detected, alternatively it will install it when it detects **Entware** installation.

[Example configuration files](/extras/rclone-backup/) that can be used with this script.

> [!IMPORTANT]
> If automatic installation of `rclone` fails then you might have to install Entware's `wget` (or `wget-ssl` when using HTTPS) to bypass the security limitations of the firmware one.

---

## [`service-event`](/scripts/service-event.sh)

This script works similarly to [service-event-end script from Asuswrt-Merlin firmware](https://github.com/RMerl/asuswrt-merlin.ng/wiki/User-scripts#service-event-end), it watches the syslog for service related events and executes appropriate actions.  

By default, integrates with all scripts present in this repository (where applicable).

---

## [`swap`](/scripts/swap.sh)

This script enables swap file on start, with configurable size and location.

_Recommended to use [`hotplug-event`](#user-content-hotplug-event) as well for better reliability._

---

## [`temperature-warning`](/scripts/temperature-warning.sh)

This script will send log message when CPU or WLAN chip temperatures reach specified threshold.

Be default, the treshold is set to <ins>80C</ins>.

> [!CAUTION]
> This script might not work correctly with every device, run `./temperature-warning check` to see if it outputs anything.

---

## [`update-notify`](/scripts/update-notify.sh)

This script will send you a notification when new router firmware is available.

By default, it runs every <ins>6 hours starting from 00:00</ins>.

**Currently supported notification providers:**

- Email
- [Telegram](https://telegram.org)
- [Pushover](https://pushover.net)
- [Pushbullet](https://www.pushbullet.com)
- Custom script

> [!WARNING]
> On some devices, the firmware update check task will not update NVRAM values correctly, making this script fail to work.

> [!TIP]
> You can test the notifications by running `./update-notify.sh test` (if it works from the cron) and `./update-notify.sh test now` (if it actually sends) commands.

> [!IMPORTANT]
> You might have to install Entware's `curl` (and `ca-bundle`) to bypass the security limitations of the one included in the stock firmware.

---

## [`uptime-reboot`](/scripts/uptime-reboot.sh)

This script will reboot your router at specified time if it's been running for a fixed amount of time.

By default, reboot happens at <ins>5AM when uptime exceeds 7 days</ins>.

---

## [`usb-network`](/scripts/usb-network.sh)

This script will add any USB networking gadget to LAN bridge interface, making it member of your LAN network.

This is a great way of running Pi-hole in your network on a [Raspberry Pi Zero connected through USB port](https://github.com/jacklul/asuswrt-usb-raspberry-pi).

_Recommended to use [`service-event`](#user-content-service-event) and [`hotplug-event`](#user-content-hotplug-event) as well for better reliability._

---

## [`vpn-firewall`](/scripts/vpn-firewall.sh)

Prevents remote side of the VPN Fusion connection from initiating connections to the router or devices in LAN.  
Has an option to allow specific ports in INPUT or FORWARD chains.

By default, interfaces for WireGuard and OpenVPN clients are affected.

> [!TIP]
> On Asuswrt-Merlin you should use **VPN director** instead.

> [!CAUTION]
> IPv6 support was not tested!

_Recommended to use [`service-event`](#user-content-service-event) as well for better reliability._

---

## [`vpn-ip-routes`](/scripts/vpn-ip-routes.sh)

Allows routing single IP addresses through specified VPN Fusion connections.

With extra scripting a basic version of domain based VPN routing can be achieved.  
Please note that without `ipset` support adding too many rules will hurt the routing performance.

> [!TIP]
> On Asuswrt-Merlin you should use **VPN director** instead.

> [!CAUTION]
> IPv6 support was not tested!

_Recommended to use [`service-event`](#user-content-service-event) as well for better reliability._

---

## [`vpn-kill-switch`](/scripts/vpn-kill-switch.sh)

This script will prevent your LAN from accessing the internet through the WAN interface.

There will be a window before this script runs when you can connect through the WAN interface, there is no way to avoid this on the official firmware.  
This also applies to situations where firmware resets firewall rules and they have to be re-added.

> [!TIP]
> On Asuswrt-Merlin you should use **VPN director** instead.

> [!CAUTION]
> IPv6 support was not tested!

_Recommended to use [`service-event`](#user-content-service-event) as well for better reliability._

---

## [`vpn-monitor`](/scripts/vpn-monitor.sh)

Monitors VPN Fusion connections and restarts them in case of connectivity failure.  
There is also an option to rotate the servers using a list, a feature known from **[VPNMON](https://github.com/ViktorJp/VPNMON-R3)**.

Only WireGuard and OpenVPN profiles are supported.

---

## [`vpn-samba`](/scripts/vpn-samba.sh)

Masquerades Samba ports to allow VPN clients to connect to your LAN shares without reconfiguring each device.

By default, default networks for WireGuard, OpenVPN and IPSec are allowed.  
_PPTP has a build-in toggle for this feature in the WebUI so it is not included by default._

> [!CAUTION]
> IPv6 support was not tested!

_Recommended to use [`service-event`](#user-content-service-event) as well for better reliability._

---

## [`vpn-vserver`](/scripts/vpn-vserver.sh)

Allows VPN Fusion connections to be affected by port forwarding rules.

By default, addresses for WireGuard and OpenVPN clients are affected.

> [!CAUTION]
> IPv6 support was not tested!

_Recommended to use [`service-event`](#user-content-service-event) as well for better reliability._

---

## [`wgs-lan-only`](/scripts/wgs-lan-only.sh)

This script will prevent clients connected to WireGuard server from accessing the internet through the router.

> [!TIP]
> On Asuswrt-Merlin you should use **VPN director** instead.

> [!CAUTION]
> IPv6 support was not tested!

_Recommended to use [`service-event`](#user-content-service-event) as well for better reliability._

---
