# shellcheck shell=sh
# Installer setup half: runs chrooted into the freshly extracted system, after
# build-image.sh's generated header has set deploy.conf + secrets.conf values
# and written provision.sh and friends into place.
#
# Everything here works without a network: identity, accounts, SSH keys,
# packages.txt + firmware from the stick's deploy repo, and arming the
# firstboot run of provision.sh, which does the rest (sudo, sshd policy,
# consoles, and patches if it can reach the internet).

set -e

echo "==> Base system config"
sysrc hostname="$DEPLOY_HOSTNAME"
# The preamble's network answers are already in rc.conf. If none were given,
# DHCP on whatever NIC is there so the box is at least reachable; SYNC holds
# boot until a lease lands, so firstboot provisioning has a network.
if ! grep -q '^ifconfig_' /etc/rc.conf; then
    sysrc ifconfig_DEFAULT="SYNCDHCP"
fi
sysrc sshd_enable="YES"
sysrc ntpd_enable="YES" ntpd_sync_on_start="YES"
sysrc dumpdev="AUTO"
sysrc clear_tmp_enable="YES"
sysrc deploy_firstboot_enable="YES"

ln -sf "/usr/share/zoneinfo/$TIMEZONE" /etc/localtime
echo "$TIMEZONE" > /var/db/zoneinfo

echo "==> Accounts"
echo "$ROOT_PW_HASH" | pw usermod root -H 0

# /bin/sh for now: DEPLOY_USER_SHELL is a package, which provision.sh installs
# and then switches the account to.
if ! pw usershow "$DEPLOY_USER" >/dev/null 2>&1; then
    echo "$USER_PW_HASH" | pw useradd -n "$DEPLOY_USER" -c "$DEPLOY_USER_FULLNAME" \
        -m -G wheel -s /bin/sh -H 0
fi

# Keys for both: root is reachable by key when SSH_PERMIT_ROOT_LOGIN allows it
for u in root "$DEPLOY_USER"; do
    home="$(pw usershow "$u" | cut -d: -f9)"
    group="$(id -gn "$u")"
    install -d -m 700 -o "$u" -g "$group" "$home/.ssh"
    printf '%s\n' "$AUTHORIZED_KEYS" > "$home/.ssh/authorized_keys"
    chown "$u:$group" "$home/.ssh/authorized_keys"
    chmod 600 "$home/.ssh/authorized_keys"
done

echo "==> Packages and firmware from the stick"
# The preamble nullfs-mounts the stick's deploy repo here. Unsigned (we built
# it), and pointed at by its own REPOS_DIR so the box's real repo config, which
# points online, is untouched.
if [ -d "$DEPLOY_REPO_MNT" ]; then
    repo_conf_dir="$(mktemp -d)"
    cat > "$repo_conf_dir/deploy.conf" <<EOF
deploy: { url: "file://$DEPLOY_REPO_MNT", signature_type: "none", enabled: yes }
EOF
    deploy_pkg() {
        ASSUME_ALWAYS_YES=yes pkg -o REPOS_DIR="$repo_conf_dir" -o IGNORE_OSVERSION=yes "$@"
    }
    deploy_pkg update
    # shellcheck disable=SC2046
    deploy_pkg install -r deploy $(grep -vE '^[[:space:]]*(#|$)' /usr/local/etc/deploy-packages.txt)

    # What this box's PCI IDs call for; anything the stick lacks is left for
    # fwget at first boot, online.
    for fw in $(fwget -q -n); do
        deploy_pkg install -r deploy "$fw" || echo "    $fw isn't on the stick; firstboot fwget will try"
    done
    rm -rf "$repo_conf_dir"
else
    echo "    No deploy repo mounted; first boot will install online"
fi

echo "==> Arming firstboot provisioning"
# rc runs scripts tagged "KEYWORD: firstboot" only while this file exists, then
# deletes it, so provisioning happens once.
touch /firstboot

echo "==> Installer setup done for $DEPLOY_HOSTNAME"
