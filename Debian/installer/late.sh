#!/bin/sh
# Runs in the installer (busybox sh) from preseed/late_command, after the base
# system is in /target and before the reboot. Copies our scripts in, lends the
# new system the stick's offline repo, and runs bootstrap.sh inside it.
#
# Output lands in the installer's syslog, which is copied to
# /var/log/installer/syslog on the installed system.

set -eu

SRC=/cdrom/deploy
T=/target
DEPLOY_DIR=/usr/local/share/deploy
REPO_MNT=/mnt/deploy-repo

. "$SRC/deploy.conf"

# The scripts live on as /usr/local/share/deploy, so bootstrap.sh and the
# network dialog can be re-run on the box later.
mkdir -p "$T$DEPLOY_DIR"
for f in bootstrap.sh deploy.conf packages.txt firstboot tools keys; do
    cp -R "$SRC/$f" "$T$DEPLOY_DIR/"
done

# Oh My Zsh isn't packaged; the stick carries a pinned copy
mkdir -p "$T/usr/local/share/ohmyzsh"
tar -xzf "$SRC/ohmyzsh.tar.gz" -C "$T/usr/local/share/ohmyzsh"

# SSH keys for root and the standard user
mkdir -p "$T/root/.ssh"
cp "$SRC/authorized_keys" "$T/root/.ssh/authorized_keys"
chmod 700 "$T/root/.ssh"
chmod 600 "$T/root/.ssh/authorized_keys"
in-target sh -c "
    install -d -m 700 -o '$DEPLOY_USER' -g '$DEPLOY_USER' ~$DEPLOY_USER/.ssh
    install -m 600 -o '$DEPLOY_USER' -g '$DEPLOY_USER' /root/.ssh/authorized_keys ~$DEPLOY_USER/.ssh/
"

# Free the space the preseed's placeholder LV held, for growing the others later
lvremove -f vg0/reserve || in-target lvremove -f vg0/reserve \
    || echo "Couldn't remove vg0/reserve; remove it by hand to free the space."

# The first boot runs the network dialog
mkdir -p "$T/var/lib/deploy"
touch "$T/var/lib/deploy/firstboot"

mkdir -p "$T$REPO_MNT"
mount -o bind "$SRC/repo" "$T$REPO_MNT"
status=0
in-target env DEPLOY_REPO="$REPO_MNT" sh "$DEPLOY_DIR/bootstrap.sh" || status=$?
umount "$T$REPO_MNT"
rmdir "$T$REPO_MNT"
exit "$status"
