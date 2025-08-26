# Archived scripts

**Scripts that no longer have any use, are broken or no longer supported.**

----

## [`disable-diag.sh`](/archive/disable-diag.sh)

This script prevents `conn_diag` from (re)starting `amas_portstatus` which likes to hog the CPU sometimes.

> [!CAUTION]
> Do not install this script if you don't have mentioned CPU usage issue.

```sh
curl -fsSL "https://raw.githubusercontent.com/jacklul/asuswrt-scripts/master/archive/disable-diag.sh" -o /jffs/scripts/disable-diag.sh
```

----

## [`led-control.sh`](/archive/led-control.sh)

> [!CAUTION]
> This script might not work on every device with the official firmware.

This script implements [scheduled LED control from Asuswrt-Merlin firmware](https://github.com/RMerl/asuswrt-merlin.ng/wiki/Scheduled-LED-control).

By default, LEDs shutdown at <ins>00:00 and turn on at 06:00</ins>.

```sh
curl -fsSL "https://raw.githubusercontent.com/jacklul/asuswrt-scripts/master/archive/led-control.sh" -o /jffs/scripts/led-control.sh
```

----

## [`netboot-download.sh`](/archive/netboot-download.sh)

Automatically download specified bootloader files from [netboot.xyz](https://netboot.xyz).

> [!TIP]
> This and [`custom-configs.sh`](#user-content-custom-configssh) can help you setup a **netboot.xyz** PXE server on the router.
>
> <details>
> <summary>Example dnsmasq.conf.add</summary>
>
> ```
> dhcp-option=66,192.168.1.1
> enable-tftp
> tftp-no-fail
> tftp-root=/tmp/netboot.xyz
> dhcp-match=set:bios,option:client-arch,0
> dhcp-boot=tag:bios,netboot.xyz.kpxe,,192.168.1.1
> dhcp-boot=tag:!bios,netboot.xyz.efi,,192.168.1.1
> ```
>
> Replace `192.168.1.1` with your router's IP address.
>
> </details>

> [!IMPORTANT]
> You might have to install Entware's `curl` (and `ca-bundle`) to bypass the security limitations of the one included in the firmware.

```sh
curl -fsSL "https://raw.githubusercontent.com/jacklul/asuswrt-scripts/master/archive/netboot-download.sh" -o /jffs/scripts/netboot-download.sh
```

----

## [`process-killer.sh`](/archive/process-killer.sh)

This script can kill processes by their names, unfortunately on the official firmware most of them will restart, there is an attempt to prevent that in that script but it is not guaranteed to work.

> [!CAUTION]
> Use this script at your own risk.

```sh
curl -fsSL "https://raw.githubusercontent.com/jacklul/asuswrt-scripts/master/archive/process-killer.sh" -o /jffs/scripts/process-killer.sh
```

----

## [`usb-mount.sh`](/archive/usb-mount.sh)

This script will mount any USB storage device in `/tmp/mnt` directory if for some reason the official firmware does not automount it for you.

_Recommended to use [`hotplug-event.sh`](/#user-content-hotplug-eventsh) as well._

```sh
curl -fsSL "https://raw.githubusercontent.com/jacklul/asuswrt-scripts/master/archive/usb-mount.sh" -o /jffs/scripts/usb-mount.sh
```
