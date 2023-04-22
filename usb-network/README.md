# Connect to LAN through USB Ethernet Gadget

This makes any device capable of becoming USB Gadget to connect to LAN network through router's USB port.

Great way to run [Pi-hole](https://pi-hole.net/) in your network on Raspberry Pi Zero!

**Warning: This cannot be used together with Entware/Optware/Asus Download Master on stock firmware.**

## How it works

Asus routers with stock firmware have the capability to run a script when USB storage device is mounted.

This is how this magic is happening:

- Router is booting, at one point USB port gets powered and Pi starts booting as well
- Pi pretends to be USB storage device, router mounts it and triggers the script
- The script on the router write a file to the mass storage device
- The script on the Pi detects that and transforms itself into USB Ethernet gadget
- The script on the router waits for the new network interface to become available and then enables it and adds it to the LAN bridge interface
- The Pi is now a member of your LAN network

The script on the router also is monitoring for the interface changes in case the Raspberry Pi reboots.

## Installation

### **On the Raspberry Pi:**

Add `dtoverlay=dwc2` to **/boot/config.txt** and `modules-load=dwc2` to **/boot/cmdline.txt** after `rootwait`.

Install `asuswrt-usb-network` script:

```bash
wget -O - "https://raw.githubusercontent.com/jacklul/asuswrt-scripts/master/usb-network/install_pi.sh" | sudo bash
```

Then enable it:
```bash
sudo systemctl enable asuswrt-usb-network.service
```

### **On the Asus router:**

Enable the SSH access in the router, connect to it and then execute this command to install required scripts:

```bash
curl "https://raw.githubusercontent.com/jacklul/asuswrt-scripts/master/usb-network/install_router.sh" | sh
```

You can also add other scripts from [scripts](/scripts) directory to `/jffs/scripts`, refer to [main README](/README.md) for more information.

### **Finish**

Power off the router, connect your Pi to router's USB port and then turn the router on - in a few minutes it should all be working smoothly!

## Configuration

You can override configuration variables in `/etc/asuswrt-usb-network.conf`.

To see the list of possible variables peek into [asuswrt-usb-network.sh](asuswrt-usb-network.sh).

## Asuswrt-Merlin

If you're running [Asuswrt-Merlin](https://www.asuswrt-merlin.net) the setup is even simplier:

- set `SKIP_MASS_STORAGE=true` in `/etc/asuswrt-usb-network.conf`
- do not run `install_router.sh` on the router
- manually place `usb-network.sh` script in `/jffs/scripts` directory and add `/jffs/scripts/usb-network.sh start &` line to `/jffs/scripts/services-start` ([reference](https://github.com/RMerl/asuswrt-merlin.ng/wiki/User-scripts))
