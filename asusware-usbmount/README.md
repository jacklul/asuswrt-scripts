# What is this?

This is my current workaround for **ASUS routers** that no longer execute command in `script_usbmount` NVRAM variable on USB mount.  
Additionally, the variable is now being cleaned by (most likely) `asd` (**Asus Security Daemon**) on newer firmware.

_Last updated: **2025-09-03**_

## How to use this?

**Your router must support ASUS Download Master.**  
Download **[asusware-usbmount.zip](asusware-usbmount.zip)** then extract **asusware.arm** directory to the root of your USB storage device.

> [!IMPORTANT]
> If your router's architecture is not ARM then you will have to replace it with the correct one in these files:
>
> - **asusware.arm/lib/ipkg/status**
> - **asusware.arm/lib/info/usb-mount-script.control**
> - **asusware.arm/lib/lists/optware.asus**
>
> You will also need to rename **asusware.arm** directory to contain the new architecture suffix as well.
>
> Known supported architecture values are `arm, mipsbig, mipsel`.  
> For `mipsel` the directory has to be called just **asusware** (no suffix!).

**The workaround script is hardcoded to launch `/jffs/scripts/usb-mount-script` script.**  
You can modify `asusware.arm/etc/init.d/S50usb-mount-script` script to run your own logic.  
You can also add more scripts to `asusware.arm/etc/init.d` directory.

### Sometimes this workaround does not work straight away - in that case do the following:

- grab another USB stick (or reformat the current one)
- plug it into the router (it has to be the only one plugged in)
- install **Download Master**
- "safely remove disk" it through the ASUS web UI
- plug back the "workaround" one - the script should execute now

### Reducing script startup delay

To reduce the delay before the script is triggered you can prevent the firmware from checking mounted filesystems for errors.

> [!WARNING]
> Do not do this if you're using the USB stick for other purposes like file share or **Entware**.  
> Power failures will lead to filesystem corruption, without **fsck** running regularly it will eventually make the filesystem broken.

```
nvram set stop_fsck=1
nvram commit
```
