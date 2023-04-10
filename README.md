# Custom scripts for AsusWRT

Requires some kind of USB storage plugged into the router for this to work.

This uses known `script_usbmount` NVRAM variable to run "startup" script on USB mount event that starts things out.

## Installation

Install startup script.

```bash
curl "https://raw.githubusercontent.com/jacklul/asuswrt-scripts/master/startup.sh" -o /jffs/startup.sh && /bin/sh /jffs/startup.sh install
```

If you would like for it to be called differently you can rename it before running it.

## Usage

Place your scripts in `/jffs/scripts`, make sure they handle "start" and "stop" arguments and are marked as executable.

Look at [scripts](scripts/) directory to figure things out.

## Extras

### [Using USB Ethernet Gadget to connect to LAN](usb-network/)
