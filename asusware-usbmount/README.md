## How to use this

Copy **asusware.arm** directory to the root of your USB storage device.

If your router's architecture is not ARM you will have to replace it with the correct one in these files:
- **asusware.arm/lib/ipkg/status**
- **asusware.arm/lib/info/usb-mount-script.control**
- **asusware.arm/lib/lists/optware.asus**

You will also need to rename **asusware.arm** directory to contain the new architecture suffix.

Known supported architecture values are `arm, mipsbig, mipsel`.
