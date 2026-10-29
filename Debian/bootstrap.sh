#!/bin/sh
# Bring a Debian box up to the standard deployed config. Idempotent: safe to
# re-run. Runs three ways:
#
#   - during install, from installer/late.sh, chrooted into the new system and
#     offline, with DEPLOY_REPO pointing at the stick's package repo;
#   - at first boot, from firstboot/firstboot.sh, online if the box is;
#   - by hand on any box, from /usr/local/share/deploy or a checkout of this
#     folder, as root:  sh bootstrap.sh
#
# Reads deploy.conf and packages.txt from beside this script.

set -eu

DEPLOY_DIR="$(cd "$(dirname "$0")" && pwd)"
. "$DEPLOY_DIR/deploy.conf"

[ "$(id -u)" -eq 0 ] || { echo "Run as root." >&2; exit 1; }

step() { echo; echo "==> $*"; }

# In the installer's chroot nothing is running, so services are enabled but not
# (re)started
if [ -d /run/systemd/system ] && ! systemd-detect-virt -q --chroot; then
    LIVE=yes
else
    LIVE=""
fi
reload() {
    if [ -n "$LIVE" ]; then systemctl reload-or-restart "$@"; fi
}

export DEBIAN_FRONTEND=noninteractive
APT="apt-get -y -q -o Dpkg::Options::=--force-confdef -o Dpkg::Options::=--force-confold"

# ============================================================================
# STEP 1: Packages
# ============================================================================
step "Packages"
# Answers for packages that would otherwise ask
debconf-set-selections <<EOF
kdump-tools kdump-tools/use_kdump boolean $([ "$KDUMP" = "yes" ] && echo true || echo false)
unattended-upgrades unattended-upgrades/enable_auto_updates boolean $([ "$AUTO_SECURITY_UPDATES" = "yes" ] && echo true || echo false)
EOF

# Anthropic's repo for claude-code. Added before the installs so a box online
# gets it from there; offline, the stick's repo already has it.
install -d -m 755 /etc/apt/keyrings
install -m 644 "$DEPLOY_DIR/keys/claude-code.asc" /etc/apt/keyrings/claude-code.asc
cat > /etc/apt/sources.list.d/claude-code.sources <<EOF
Types: deb
URIs: https://downloads.claude.ai/claude-code/apt/$CLAUDE_CODE_CHANNEL
Suites: $CLAUDE_CODE_CHANNEL
Components: main
Signed-By: /etc/apt/keyrings/claude-code.asc
EOF

PACKAGES="$(grep -vE '^[[:space:]]*(#|$)' "$DEPLOY_DIR/packages.txt")"
ONLINE=""
if [ -n "${DEPLOY_REPO:-}" ]; then
    # The stick's repo only: it holds every package and dependency, at the
    # versions current when the stick was built
    list="$(mktemp)"
    echo "deb [trusted=yes] file:$DEPLOY_REPO ./" > "$list"
    REPO_OPTS="-o Dir::Etc::SourceList=$list -o Dir::Etc::SourceParts=/nonexistent"
    # shellcheck disable=SC2086
    $APT $REPO_OPTS update
    # shellcheck disable=SC2086
    $APT $REPO_OPTS --no-install-recommends install $PACKAGES
    rm -f "$list" /var/lib/apt/lists/*deploy-repo*
elif $APT update; then
    ONLINE=yes
    # shellcheck disable=SC2086
    $APT --no-install-recommends install $PACKAGES
else
    echo "Package mirrors unreachable: skipping installs and updates."
fi

# ============================================================================
# STEP 2: Package sources for later
# ============================================================================
# The installer ran without a mirror, so point apt at Debian's, with
# non-free-firmware for firmware updates
step "Package sources"
. /etc/os-release
cat > /etc/apt/sources.list.d/debian.sources <<EOF
Types: deb
URIs: http://deb.debian.org/debian
Suites: $VERSION_CODENAME $VERSION_CODENAME-updates
Components: main contrib non-free non-free-firmware
Signed-By: /usr/share/keyrings/debian-archive-keyring.gpg

Types: deb
URIs: http://security.debian.org/debian-security
Suites: $VERSION_CODENAME-security
Components: main contrib non-free non-free-firmware
Signed-By: /usr/share/keyrings/debian-archive-keyring.gpg
EOF
# Only the commented-out cdrom line is left in the old file
if [ -f /etc/apt/sources.list ] && ! grep -qE '^[[:space:]]*deb ' /etc/apt/sources.list; then
    rm -f /etc/apt/sources.list
fi

if [ "$AUTO_SECURITY_UPDATES" = "yes" ]; then
    cat > /etc/apt/apt.conf.d/20auto-upgrades <<'EOF'
APT::Periodic::Update-Package-Lists "1";
APT::Periodic::Unattended-Upgrade "1";
EOF
    # Claude Code updates itself everywhere else; here apt does it nightly
    cat > /etc/apt/apt.conf.d/52deploy-claude-code <<EOF
Unattended-Upgrade::Origins-Pattern:: "origin=Anthropic,codename=$CLAUDE_CODE_CHANNEL";
EOF
else
    rm -f /etc/apt/apt.conf.d/20auto-upgrades /etc/apt/apt.conf.d/52deploy-claude-code
fi

# ============================================================================
# STEP 3: The standard user
# ============================================================================
if id "$DEPLOY_USER" >/dev/null 2>&1; then
    step "User $DEPLOY_USER"
    usermod -aG sudo "$DEPLOY_USER"
    if grep -qx "$DEPLOY_USER_SHELL" /etc/shells; then
        usermod -s "$DEPLOY_USER_SHELL" "$DEPLOY_USER"
    else
        echo "$DEPLOY_USER_SHELL isn't installed; leaving the login shell alone."
    fi

    # Oh My Zsh comes from the stick; a box built some other way clones it
    OMZ=/usr/local/share/ohmyzsh
    if [ ! -f "$OMZ/oh-my-zsh.sh" ] && [ -n "$ONLINE" ]; then
        rm -rf "$OMZ"
        git clone -q https://github.com/ohmyzsh/ohmyzsh.git "$OMZ"
        git -C "$OMZ" checkout -q "$OHMYZSH_REF"
    fi

    # Same as the FreeBSD standard: only written if missing, so it's never
    # clobbered; that also stops zsh's new-user menu at first login.
    user_home="$(getent passwd "$DEPLOY_USER" | cut -d: -f6)"
    if [ "${DEPLOY_USER_SHELL##*/}" = "zsh" ] && [ ! -e "$user_home/.zshrc" ]; then
        cat > "$user_home/.zshrc" <<'EOF'
# Written by bootstrap.sh; edit freely, it won't be overwritten.
export ZSH=/usr/local/share/ohmyzsh
# $ZSH is root-owned, so the cache lives with the user
ZSH_CACHE_DIR="$HOME/.cache/oh-my-zsh"
# Pinned copy from the deploy stick; don't let it try to self-update
zstyle ':omz:update' mode disabled

ZSH_THEME="robbyrussell"
plugins=(git)

source $ZSH/oh-my-zsh.sh

export PATH="$HOME/.local/bin:$PATH"

alias ll='ls -lah'
alias gs='git status'
alias gp='git pull'

# Starship over SSH only. Its default prompt uses Nerd Font glyphs, which the
# console (monitor, IPKVM, serial) can't draw, so there robbyrussell stays.
if [[ -n $SSH_CONNECTION ]] && (( $+commands[starship] )); then
    eval "$(starship init zsh)"
fi
EOF
        chown "$DEPLOY_USER:$(id -gn "$DEPLOY_USER")" "$user_home/.zshrc"
    fi
else
    echo "No $DEPLOY_USER account; skipping its setup."
fi

# ============================================================================
# STEP 3b: Neovim, tree-sitter, herdr, and LazyVim for the standard user
# ============================================================================
# Debian's Neovim is too old for LazyVim. The upstream tools come from the
# stick; online, every run moves them to the newest release, and a failed
# download keeps what's there.
step "Upstream tools"
if [ -n "$ONLINE" ]; then
    upstream="$(mktemp -d)"
    "$DEPLOY_DIR/tools/fetch-upstream" "$upstream" \
        || echo "Some downloads failed; keeping what's installed for those."
    "$DEPLOY_DIR/tools/install-upstream" "$upstream"
    rm -rf "$upstream"
elif [ -n "${DEPLOY_REPO:-}" ]; then
    "$DEPLOY_DIR/tools/install-upstream" "$DEPLOY_REPO/upstream"
else
    echo "Offline; leaving them as they are."
fi
if dpkg -s neovim >/dev/null 2>&1; then
    $APT purge --autoremove neovim neovim-runtime
fi

# An existing ~/.config/nvim is never touched. The stick carries LazyVim
# prebuilt; online, it's set up fresh.
if id "$DEPLOY_USER" >/dev/null 2>&1; then
    step "LazyVim for $DEPLOY_USER"
    user_home="$(getent passwd "$DEPLOY_USER" | cut -d: -f6)"
    if [ -e "$user_home/.config/nvim" ]; then
        echo "Already set up."
    elif [ -n "${DEPLOY_REPO:-}" ] && [ -f "$DEPLOY_REPO/upstream/lazyvim.tar.gz" ]; then
        tar -xzf "$DEPLOY_REPO/upstream/lazyvim.tar.gz" -C "$user_home"
        chown -R "$DEPLOY_USER:$(id -gn "$DEPLOY_USER")" \
            "$user_home/.config" "$user_home/.local"
    elif [ -n "$ONLINE" ] && [ -x /usr/local/bin/nvim ]; then
        su "$DEPLOY_USER" -c "$DEPLOY_DIR/tools/lazyvim-setup" \
            || echo "LazyVim setup failed; run $DEPLOY_DIR/tools/lazyvim-setup as $DEPLOY_USER."
    else
        echo "Offline and not on the stick; skipping."
    fi
fi

# ============================================================================
# STEP 4: sshd
# ============================================================================
# sshd keeps the first value it reads, and Debian's sshd_config includes
# sshd_config.d/*.conf at the very top, so this drop-in wins.
step "sshd"
cat > /etc/ssh/sshd_config.d/10-deploy.conf <<EOF
# Managed by bootstrap.sh; edits here are overwritten.
PermitRootLogin $SSH_PERMIT_ROOT_LOGIN
UseDNS no
EOF
mkdir -p /run/sshd
sshd -t
systemctl enable ssh
reload ssh

# ============================================================================
# STEP 5: Network: NetworkManager owns every interface
# ============================================================================
# The installer ran without a network, so /etc/network/interfaces only has lo.
# Anything ifupdown doesn't list, NetworkManager manages; until the first-boot
# dialog says otherwise, it runs DHCP on every wired port.
step "NetworkManager"
if grep -qvE '^[[:space:]]*(#|$|auto lo|iface lo|source)' /etc/network/interfaces 2>/dev/null; then
    echo "/etc/network/interfaces configures more than lo; those ports stay with ifupdown."
fi
systemctl enable NetworkManager

# ============================================================================
# STEP 6: Consoles (monitor / IPKVM / serial)
# ============================================================================
# The LAST console= is the one boot messages and the emergency shell use, so
# tty0 (video) goes last. A getty starts on ttyS0 automatically because it's a
# kernel console; on a box without a serial port it's simply absent.
step "Consoles"
mkdir -p /etc/default/grub.d
if [ "$SERIAL_CONSOLE" = "yes" ]; then
    cat > /etc/default/grub.d/10-deploy.cfg <<'EOF'
# Managed by bootstrap.sh
GRUB_TIMEOUT=5
GRUB_CMDLINE_LINUX="console=ttyS0,115200n8 console=tty0"
GRUB_TERMINAL="console serial"
GRUB_SERIAL_COMMAND="serial --unit=0 --speed=115200"
EOF
else
    cat > /etc/default/grub.d/10-deploy.cfg <<'EOF'
# Managed by bootstrap.sh
GRUB_TIMEOUT=5
EOF
fi

# ============================================================================
# STEP 7: Post-mortem records
# ============================================================================
# For working out why a box died or restarted:
#   journalctl -b -1          the previous boot's log, kept across reboots
#   /var/crash                kernel crash dumps (kdump-tools)
#   memhog                    biggest memory users from atop's history
#   lastcomm                  every process that exited (acct)
step "Post-mortem records"
mkdir -p /etc/systemd/journald.conf.d
cat > /etc/systemd/journald.conf.d/10-deploy.conf <<'EOF'
# Managed by bootstrap.sh
[Journal]
Storage=persistent
SystemMaxUse=200M
EOF
reload systemd-journald

# atop snapshots every process every 10 minutes into /var/log/atop, one file a
# day, deleted after 14 days (a few MB a day on a box like this)
if [ -f /etc/default/atop ]; then
    sed -i -e 's/^LOGINTERVAL=.*/LOGINTERVAL=600/' \
           -e 's/^LOGGENERATIONS=.*/LOGGENERATIONS=14/' /etc/default/atop
    systemctl enable atop
    reload atop
fi
install -m 755 "$DEPLOY_DIR/tools/memhog" /usr/local/bin/memhog

systemctl enable acct 2>/dev/null || true
if [ "$KDUMP" = "yes" ]; then
    systemctl enable kdump-tools 2>/dev/null || true
fi

# ============================================================================
# STEP 8: First-boot dialog
# ============================================================================
install -m 755 "$DEPLOY_DIR/firstboot/deploy-netconfig" /usr/local/sbin/deploy-netconfig
install -m 644 "$DEPLOY_DIR/firstboot/deploy-firstboot.service" /etc/systemd/system/
systemctl enable deploy-firstboot.service
ln -sf "$DEPLOY_DIR/bootstrap.sh" /usr/local/sbin/deploy-bootstrap

# ============================================================================
# STEP 9: Updates
# ============================================================================
if [ -n "$ONLINE" ]; then
    step "Updates"
    $APT full-upgrade
fi

# GRUB settings and kdump's crashkernel= both live in /etc/default/grub.d
update-grub

echo
echo "Bootstrapped $(hostname) (Debian $(cat /etc/debian_version), kernel $(uname -r))"
if [ -f /var/run/reboot-required ]; then
    echo "A reboot is needed to finish updates."
fi
