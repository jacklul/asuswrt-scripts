## How to use this

Download **[asusware-usbmount.zip](asusware-usbmount.zip)** then extract **asusware.arm** directory to the root of your USB storage device.

> [!IMPORTANT]
> If your router's architecture is not ARM you will have to replace it with the correct one in these files:
> - **asusware.arm/lib/ipkg/status**
> - **asusware.arm/lib/info/usb-mount-script.control**
> - **asusware.arm/lib/lists/optware.asus**
> 
> You will also need to rename **asusware.arm** directory to contain the new architecture suffix.
> 
> Known supported architecture values are `arm, mipsbig, mipsel`.  
> For `mipsel` the directory has to be called just **asusware**.

> [!WARNING]
> If you installed `scripts-startup.sh` script in a custom path (`/jffs/scripts-startup.sh` is the default) you will have to correct the value of `TARGET_SCRIPT` variable in `asusware.arm/etc/init.d/S50usb-mount-script` file!

### Sometimes this workaround does not work straight away - in that case do the following:

- grab another USB stick (or reformat current one)
- plug it into the router (it has to be the only one plugged in)
- install Download Master
- unplug it and plug back the "workaround" one - everything should be working now

I'm yet to discover how to avoid this, perhaps it has something to do with `apps_` variables.

### This can reduce scripts startup delay:

```
nvram set stop_fsck=1
nvram commit
```

_This prevents the firmware from checking device containing `asusware` directory for filesystem errors._
