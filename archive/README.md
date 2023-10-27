# Archived scripts

These scripts are no longer supported.

## [`tailscale.sh`](/archive/tailscale.sh)

**Use Entware package instead of this script when possible!**

This script installs [Tailscale](https://tailscale.com) service on your router, allowing it to be used as an exit node.

You should probably store the binaries on USB drive but the script has also an option to automatically download the binaries - make sure your device has enough memory for this though.

Recommended to use [`service-event.sh`](#user-content-service-eventsh) as well.

```sh
curl -fsSL "https://raw.githubusercontent.com/jacklul/asuswrt-scripts/master/archive/tailscale.sh" -o /jffs/scripts/tailscale.sh
```
