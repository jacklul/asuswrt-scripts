**You can override config variables for scripts by creating `.conf` with the same base name as the script.**

Convenient install commands (install what you need, not everything!):
```sh
curl "https://raw.githubusercontent.com/jacklul/asuswrt-scripts/master/scripts/conditional-reboot.sh" -o /jffs/scripts/conditional-reboot.sh

curl "https://raw.githubusercontent.com/jacklul/asuswrt-scripts/master/scripts/disable-wps.sh" -o /jffs/scripts/disable-wps.sh

curl "https://raw.githubusercontent.com/jacklul/asuswrt-scripts/master/scripts/dynamic-dns.sh" -o /jffs/scripts/dynamic-dns.sh

curl "https://raw.githubusercontent.com/jacklul/asuswrt-scripts/master/scripts/force-dns.sh" -o /jffs/scripts/force-dns.sh

curl "https://raw.githubusercontent.com/jacklul/asuswrt-scripts/master/scripts/led-control.sh" -o /jffs/scripts/led-control.sh

curl "https://raw.githubusercontent.com/jacklul/asuswrt-scripts/master/scripts/process-killer.sh" -o /jffs/scripts/process-killer.sh

curl "https://raw.githubusercontent.com/jacklul/asuswrt-scripts/master/scripts/rclone-backup.sh" -o /jffs/scripts/rclone-backup.sh
curl "https://raw.githubusercontent.com/jacklul/asuswrt-scripts/master/scripts/rclone-backup.list" -o /jffs/scripts/rclone-backup.list

curl "https://raw.githubusercontent.com/jacklul/asuswrt-scripts/master/scripts/swap.sh" -o /jffs/scripts/swap.sh

curl "https://raw.githubusercontent.com/jacklul/asuswrt-scripts/master/scripts/syslog-move.sh" -o /jffs/scripts/syslog-move.sh

curl "https://raw.githubusercontent.com/jacklul/asuswrt-scripts/master/scripts/temperature-warning.sh" -o /jffs/scripts/temperature-warning.sh

curl "https://raw.githubusercontent.com/jacklul/asuswrt-scripts/master/scripts/update-notify.sh" -o /jffs/scripts/update-notify.sh

curl "https://raw.githubusercontent.com/jacklul/asuswrt-scripts/master/scripts/update-scripts.sh" -o /jffs/scripts/update-scripts.sh

curl "https://raw.githubusercontent.com/jacklul/asuswrt-scripts/master/scripts/usb-network.sh" -o /jffs/scripts/usb-network.sh

chmod +x /jffs/scripts/*.sh
```
