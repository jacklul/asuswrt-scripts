# What is this?

This is my current workaround for **ASUS routers** that no longer execute commands in the `script_usbmount` NVRAM variable on USB mount.  
Additionally, the variable is now being cleaned by (most likely) `asd` (**Asus Security Daemon**) on newer firmware.

_Last updated: **2025-09-12**_

## Installation

**Your router must have a USB port and support ASUS Download Master.**  

### Automatic

The easiest way to install this is to run the installer while having <ins>only one</ins> USB storage plugged in:

```sh
curl "https://raw.githubusercontent.com/jacklul/asuswrt-scripts/master/asusware-usb-mount-script/asusware-usb-mount-script.sh" | sh
```

<details>
<summary>curl is not available? try wget</summary>

```sh
wget "https://raw.githubusercontent.com/jacklul/asuswrt-scripts/master/asusware-usb-mount-script/asusware-usb-mount-script.sh" -O - | sh
```

</details>

### Manual

If the installer fails for some reason then you can download **[asusware-usb-mount-script.zip](asusware-usb-mount-script.zip)** then extract **asusware.arm** directory to the root of your USB storage device.

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
> For `mipsel`, the directory has to be called just **asusware** (no suffix).

## Usage

**The script is hardcoded to launch `/jffs/scripts/usb-mount-script` script after USB storage is mounted.**  
You can modify `asusware.arm/etc/init.d/S50usb-mount-script` script to run your own logic.  
You can also add more scripts to `asusware.arm/etc/init.d` directory if you wish.

### If the script does not seem to start...

- grab another USB stick
- plug it into the router (it has to be the only one plugged in)
- install **Download Master**
- "safely remove disk" through the ASUS web UI 
- unplug the USB stick and reboot the router
- plug in the "workaround" stick - it should work now

### Reducing script startup delay

To reduce the delay before the script is triggered you can prevent the firmware from checking mounted filesystems for errors.

> [!WARNING]
> Do not do this if you're using the USB stick for other purposes like file share or **Entware**.  
> Power failures will lead to filesystem corruption, without **fsck** running regularly it will eventually make the filesystem broken.

```
nvram set stop_fsck=1
nvram commit
```
