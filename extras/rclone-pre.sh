#!/bin/sh
# Save NVRAM settings so rclone-backup can back them up

nvram show > /tmp/nvram.txt 2> /dev/null
nvram save /tmp/nvram.cfg
