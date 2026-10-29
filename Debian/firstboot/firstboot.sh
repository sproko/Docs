#!/bin/sh
# First boot, from deploy-firstboot.service: the network dialog on the console,
# then bootstrap.sh again, which installs updates if the box can reach Debian's
# mirrors. Skipping the dialog leaves DHCP on every wired port, so a box with
# nobody at the console still comes up reachable over SSH.

LOG=/var/log/deploy-firstboot.log

chvt 2
if ! /usr/local/sbin/deploy-netconfig; then
    echo "Network dialog skipped: DHCP on every wired port. Run deploy-netconfig to change it."
fi

clear
echo "Waiting for the network, then checking for updates..."
nm-online -q -t 60 || true
sh /usr/local/share/deploy/bootstrap.sh 2>&1 | tee "$LOG"

rm -f /var/lib/deploy/firstboot
echo
echo "First boot done (log: $LOG)."
if [ -f /var/run/reboot-required ]; then
    echo "Rebooting to finish updates..."
    sleep 5
    systemctl reboot
fi
sleep 3
chvt 1
