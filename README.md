# Custom scripts for AsusWRT

Requires some kind of USB storage plugged into the router for this to work.

This uses known `script_usbmount` NVRAM variable to run "startup" script on USB mount event that starts things out.

If you're running Asuswrt-Merlin you might be interested in using [my addon](Merlin/) instead.

## Installation

Install startup script:

```bash
curl "https://raw.githubusercontent.com/jacklul/asuswrt-scripts/master/startup.sh" -o /jffs/startup.sh && /bin/sh /jffs/startup.sh install
```

If you would like for it to be called differently you can rename it before running it.

Then install scripts you want to use, grab them [from here](scripts/).
