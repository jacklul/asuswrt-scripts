# What is this?

This is my current workaround for **Asus routers** that no longer execute command in `script_usbmount` NVRAM variable on USB mount.  
The variable is being cleaned by `asd` (**Asus Security Daemon**).

_Last updated: **2025-08-27**_

## How to use this?

Download **[asusware-usbmount.zip](asusware-usbmount.zip)** then extract **asusware.arm** directory to the root of your USB storage device.

**The workaround is hardcoded to launch whichever exists first:**

- command in `script_usbmount` NVRAM variable
- `/jffs/scripts/usb-mount-script` script
- `/jffs/scripts/scripts-startup.sh` script (with `start` argument)
- `/jffs/scripts-startup.sh` script (with `start` argument)

You can also modify or replace `asusware.arm/etc/init.d/S50usb-mount-script` script to run your own logic.

> [!IMPORTANT]
> If your router's architecture is not ARM you will have to replace it with the correct one in these files:
>
> - **asusware.arm/lib/ipkg/status**
> - **asusware.arm/lib/info/usb-mount-script.control**
> - **asusware.arm/lib/lists/optware.asus**
>
> You will also need to rename **asusware.arm** directory to contain the new architecture suffix as well.
>
> Known supported architecture values are `arm, mipsbig, mipsel`.  
> For `mipsel` the directory has to be called just **asusware** (no suffix!).

### Sometimes this workaround does not work straight away - in that case do the following:

- grab another USB stick (or reformat the current one)
- plug it into the router (it has to be the only one plugged in)
- install Download Master
- unplug it, preferably cleanly unmount it from the web UI first
- plug back the "workaround" one - the script should be executed now

### Reducing script startup delay

To reduce the delay before the script is triggered you can prevent the firmware from checking mounted filesystems for errors.

> [!WARNING]
> Do not do this if you're using the USB stick for other purposes like file share or Entware.  
> Power failures will lead to filesystem corruption, without **fsck** running regularly it will eventually make the filesystem unreadable.

```
nvram set stop_fsck=1
nvram commit
```
