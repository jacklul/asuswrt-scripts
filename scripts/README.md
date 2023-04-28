**You can override config variables for scripts by creating `.conf` with the same base name as the script.**

**If there is another file with the same base name as the script then it is required for that script to work.**

Convenient install commands (install what you need, not everything!):
```sh
cur -fsSL "https://raw.githubusercontent.com/jacklul/asuswrt-scripts/master/scripts/conditional-reboot.sh" -o /jffs/scripts/conditional-reboot.sh

cur -fsSL "https://raw.githubusercontent.com/jacklul/asuswrt-scripts/master/scripts/disable-wps.sh" -o /jffs/scripts/disable-wps.sh

cur -fsSL "https://raw.githubusercontent.com/jacklul/asuswrt-scripts/master/scripts/dynamic-dns.sh" -o /jffs/scripts/dynamic-dns.sh

cur -fsSL "https://raw.githubusercontent.com/jacklul/asuswrt-scripts/master/scripts/force-dns.sh" -o /jffs/scripts/force-dns.sh

cur -fsSL "https://raw.githubusercontent.com/jacklul/asuswrt-scripts/master/scripts/guest-password.sh" -o /jffs/scripts/guest-password.sh
cur -fsSL "https://raw.githubusercontent.com/jacklul/asuswrt-scripts/master/scripts/guest-password.html" -o /jffs/scripts/guest-password.html

cur -fsSL "https://raw.githubusercontent.com/jacklul/asuswrt-scripts/master/scripts/led-control.sh" -o /jffs/scripts/led-control.sh

cur -fsSL "https://raw.githubusercontent.com/jacklul/asuswrt-scripts/master/scripts/process-killer.sh" -o /jffs/scripts/process-killer.sh

cur -fsSL "https://raw.githubusercontent.com/jacklul/asuswrt-scripts/master/scripts/rclone-backup.sh" -o /jffs/scripts/rclone-backup.sh
cur -fsSL "https://raw.githubusercontent.com/jacklul/asuswrt-scripts/master/scripts/rclone-backup.list" -o /jffs/scripts/rclone-backup.list

cur -fsSL "https://raw.githubusercontent.com/jacklul/asuswrt-scripts/master/scripts/samba-masquerade.sh" -o /jffs/scripts/samba-masquerade.sh

cur -fsSL "https://raw.githubusercontent.com/jacklul/asuswrt-scripts/master/scripts/service-event.sh" -o /jffs/scripts/service-event.sh

cur -fsSL "https://raw.githubusercontent.com/jacklul/asuswrt-scripts/master/scripts/swap.sh" -o /jffs/scripts/swap.sh

cur -fsSL "https://raw.githubusercontent.com/jacklul/asuswrt-scripts/master/scripts/tailscale.sh" -o /jffs/scripts/tailscale.sh

cur -fsSL "https://raw.githubusercontent.com/jacklul/asuswrt-scripts/master/scripts/temperature-warning.sh" -o /jffs/scripts/temperature-warning.sh

cur -fsSL "https://raw.githubusercontent.com/jacklul/asuswrt-scripts/master/scripts/update-notify.sh" -o /jffs/scripts/update-notify.sh

cur -fsSL "https://raw.githubusercontent.com/jacklul/asuswrt-scripts/master/scripts/update-scripts.sh" -o /jffs/scripts/update-scripts.sh

cur -fsSL "https://raw.githubusercontent.com/jacklul/asuswrt-scripts/master/scripts/usb-network.sh" -o /jffs/scripts/usb-network.sh

cur -fsSL "https://raw.githubusercontent.com/jacklul/asuswrt-scripts/master/scripts/vpn-killswitch.sh" -o /jffs/scripts/vpn-killswitch.sh

cur -fsSL "https://raw.githubusercontent.com/jacklul/asuswrt-scripts/master/scripts/wgs-lanonly.sh" -o /jffs/scripts/wgs-lanonly.sh

chmod +x /jffs/scripts/*.sh
```
