#!/bin/sh
# Save NVRAM settings so rclone-backup can back them up

nvram show > /root/nvram.txt 2> /dev/null
nvram save /root/nvram.cfg
