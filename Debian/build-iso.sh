#!/bin/sh
# Build the deploy installer: a copy of the stock Debian netinst ISO that
# installs unattended (bar picking the disk) from the preseed, plus an offline
# package repo, so the install needs no network.
#
# The host only needs Docker: the work runs in a debian:trixie container, which
# also makes the downloaded packages match the release being installed.
#
#   ./make-secrets.sh                                  # once, writes secrets.conf
#   ./build-iso.sh ~/Downloads/debian-13.7.0-amd64-netinst.iso
#   sudo dd if=build/debian-13.7.0-amd64-deploy.iso of=/dev/sdX bs=4M conv=fsync status=progress

set -eu

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

# ============================================================================
# On the host: hand over to the container
# ============================================================================
if [ "${1:-}" != "--in-container" ]; then
    SRC_ISO="${1:-}"
    if [ -z "$SRC_ISO" ] || [ ! -f "$SRC_ISO" ]; then
        echo "Usage: $0 <debian-*-amd64-netinst.iso>" >&2
        exit 1
    fi
    [ -f "$SCRIPT_DIR/secrets.conf" ] || { echo "No secrets.conf: run ./make-secrets.sh first." >&2; exit 1; }
    command -v docker >/dev/null || { echo "Docker is required." >&2; exit 1; }
    SRC_ISO="$(cd "$(dirname "$SRC_ISO")" && pwd)/$(basename "$SRC_ISO")"
    mkdir -p "$SCRIPT_DIR/build"
    exec docker run --rm \
        -v "$SCRIPT_DIR:/work" \
        -v "$SRC_ISO:/src.iso:ro" \
        -e ISO_NAME="$(basename "$SRC_ISO")" \
        -e HOST_UID="$(id -u)" -e HOST_GID="$(id -g)" \
        debian:trixie sh /work/build-iso.sh --in-container
fi

# ============================================================================
# In the container
# ============================================================================
cd /work
. ./deploy.conf
. ./secrets.conf
BUILD=/work/build
STAGE="$BUILD/iso"
OUT_ISO="$BUILD/$(echo "$ISO_NAME" | sed 's/-netinst\.iso$//')-deploy.iso"
export DEBIAN_FRONTEND=noninteractive

step() { echo; echo "==> $*"; }
# Everything here is made as root; hand it back to whoever ran the build
trap 'chown -R "$HOST_UID:$HOST_GID" "$BUILD"' EXIT

step "Build tools"
sed -i 's/^Components: main$/Components: main contrib non-free non-free-firmware/' \
    /etc/apt/sources.list.d/debian.sources
apt-get update -q
apt-get install -y -q --no-install-recommends xorriso cpio apt-utils git curl ca-certificates

# ----------------------------------------------------------------------------
# Offline repo: packages.txt and everything they depend on
# ----------------------------------------------------------------------------
# Resolved against an EMPTY package database, so it includes every dependency
# down to libc, at today's versions. The installed base on the target may be
# older than what some of these need; with the whole chain here, apt upgrades
# what it has to from the stick.
step "Offline package repo"
# Anthropic's repo too, for claude-code, set up the way bootstrap.sh does it
install -d /etc/apt/keyrings
cp keys/claude-code.asc /etc/apt/keyrings/
cat > /etc/apt/sources.list.d/claude-code.sources <<EOF
Types: deb
URIs: https://downloads.claude.ai/claude-code/apt/$CLAUDE_CODE_CHANNEL
Suites: $CLAUDE_CODE_CHANNEL
Components: main
Signed-By: /etc/apt/keyrings/claude-code.asc
EOF
apt-get update -q
REPO="$BUILD/repo"
rm -rf "$REPO"
mkdir -p "$REPO/partial"
empty_status="$(mktemp)"
# shellcheck disable=SC2046
apt-get install -y -q --download-only --no-install-recommends \
    -o Dir::State::status="$empty_status" \
    -o Dir::Cache::archives="$REPO" \
    $(grep -vE '^[[:space:]]*(#|$)' packages.txt)
rm -rf "$REPO/partial" "$REPO/lock"
(cd "$REPO" && apt-ftparchive packages . > Packages && gzip -9kf Packages \
    && apt-ftparchive release . > Release)
echo "Repo: $(ls "$REPO"/*.deb | wc -l) packages, $(du -sh "$REPO" | cut -f1)"

step "Oh My Zsh at $OHMYZSH_REF"
rm -rf "$BUILD/ohmyzsh"
git clone -q https://github.com/ohmyzsh/ohmyzsh.git "$BUILD/ohmyzsh"
git -C "$BUILD/ohmyzsh" archive --format=tar.gz -o "$BUILD/ohmyzsh.tar.gz" "$OHMYZSH_REF"

# Neovim, tree-sitter and herdr ride in the repo folder, which the installer
# already lends the new system
step "Upstream tools"
tools/fetch-upstream "$REPO/upstream"

# LazyVim's plugins, parsers and Mason tools, built here as the standard user
# so the paths inside match, and so a box's first nvim needs no network
step "LazyVim"
apt-get install -y -q --no-install-recommends gcc libc6-dev ripgrep fd-find fzf unzip
tools/install-upstream "$REPO/upstream"
id "$DEPLOY_USER" >/dev/null 2>&1 || useradd -m "$DEPLOY_USER"
user_home="$(getent passwd "$DEPLOY_USER" | cut -d: -f6)"
rm -rf "$user_home/.config/nvim" "$user_home/.local/share/nvim" "$user_home/.local/state/nvim"
su "$DEPLOY_USER" -c /work/tools/lazyvim-setup
tar -czf "$REPO/upstream/lazyvim.tar.gz" -C "$user_home" \
    .config/nvim .local/share/nvim .local/state/nvim
echo "LazyVim: $(du -sh "$REPO/upstream/lazyvim.tar.gz" | cut -f1)"

# ----------------------------------------------------------------------------
# The ISO tree
# ----------------------------------------------------------------------------
step "Unpacking $ISO_NAME"
rm -rf "$STAGE"
xorriso -osirrox on -indev /src.iso -extract / "$STAGE" 2>/dev/null
chmod -R u+w "$STAGE"

# Our scripts and repo, as /cdrom/deploy in the installer
D="$STAGE/deploy"
mkdir -p "$D"
cp -R bootstrap.sh deploy.conf packages.txt firstboot tools keys installer "$D/"
cp -R "$REPO" "$D/repo"
cp "$BUILD/ohmyzsh.tar.gz" "$D/"
printf '%s\n' "$AUTHORIZED_KEYS" > "$D/authorized_keys"

# The preseed goes inside the initrd rather than on the ISO, so it's read
# before the first question (language, keyboard) is asked. partman sizes are
# in MB (10^6 bytes), so GB x 1074 gives GiB, which is what lsblk and df show.
step "Preseed"
awk -v locale="$LOCALE" -v keymap="$KEYMAP" -v hostname="$DEFAULT_HOSTNAME" \
    -v tz="$TIMEZONE" -v user="$DEPLOY_USER" -v fullname="$DEPLOY_USER_FULLNAME" \
    -v root_mb="$((ROOT_SIZE_GB * 1074))" -v swap_mb="$((SWAP_SIZE_GB * 1074))" \
    -v srv_mb="$((SRV_SIZE_GB * 1074))" \
    -v root_pw="$ROOT_PW_HASH" -v user_pw="$USER_PW_HASH" '
    {
        gsub(/@LOCALE@/, locale); gsub(/@KEYMAP@/, keymap); gsub(/@HOSTNAME@/, hostname)
        gsub(/@TIMEZONE@/, tz); gsub(/@USER@/, user); gsub(/@USER_FULLNAME@/, fullname)
        gsub(/@ROOT_MB@/, root_mb); gsub(/@SWAP_MB@/, swap_mb); gsub(/@SRV_MB@/, srv_mb)
        # index/substr, not gsub: the hashes are full of "$" and "/"
        if ((i = index($0, "@ROOT_PW_HASH@")) > 0) $0 = substr($0, 1, i - 1) root_pw substr($0, i + 14)
        if ((i = index($0, "@USER_PW_HASH@")) > 0) $0 = substr($0, 1, i - 1) user_pw substr($0, i + 14)
        print
    }' installer/preseed.cfg > "$BUILD/preseed.cfg"
if grep -n '@[A-Z_]*@' "$BUILD/preseed.cfg"; then
    echo "Unfilled placeholders in the preseed" >&2
    exit 1
fi

INITRD="$STAGE/install.amd/initrd.gz"
mkdir -p "$BUILD/initrd-add"
cp "$BUILD/preseed.cfg" "$BUILD/initrd-add/preseed.cfg"
gunzip -c "$INITRD" > "$BUILD/initrd"
(cd "$BUILD/initrd-add" && echo preseed.cfg | cpio -H newc -o -A -R 0:0 -F "$BUILD/initrd" 2>/dev/null)
gzip -9c "$BUILD/initrd" > "$INITRD"
rm -rf "$BUILD/initrd" "$BUILD/initrd-add"

# ----------------------------------------------------------------------------
# Boot menus: the deploy install by default, the stock graphical installer
# (untouched initrd, so no preseed) and rescue mode for anything else
# ----------------------------------------------------------------------------
step "Boot menus"
cat > "$STAGE/boot/grub/grub.cfg" <<'EOF'
set default=0
set timeout=10
if serial --unit=0 --speed=115200; then
    terminal_input --append serial
    terminal_output --append serial
fi

menuentry 'Deploy install (ERASES the disk you pick)' {
    linux  /install.amd/vmlinuz --- quiet
    initrd /install.amd/initrd.gz
}
menuentry 'Deploy install, serial console (ttyS0, 115200)' {
    linux  /install.amd/vmlinuz console=ttyS0,115200n8 ---
    initrd /install.amd/initrd.gz
}
menuentry 'Stock Debian installer (graphical, no automation)' {
    linux  /install.amd/vmlinuz vga=788 --- quiet
    initrd /install.amd/gtk/initrd.gz
}
menuentry 'Rescue mode' {
    linux  /install.amd/vmlinuz vga=788 rescue/enable=true --- quiet
    initrd /install.amd/gtk/initrd.gz
}
EOF
# BIOS boot. Timeout is in tenths of a second.
cat > "$STAGE/isolinux/isolinux.cfg" <<'EOF'
serial 0 115200
default deploy
prompt 1
timeout 100
display deploy.msg
label deploy
    kernel /install.amd/vmlinuz
    append initrd=/install.amd/initrd.gz --- quiet
label serial
    kernel /install.amd/vmlinuz
    append initrd=/install.amd/initrd.gz console=ttyS0,115200n8 ---
label stock
    kernel /install.amd/vmlinuz
    append vga=788 initrd=/install.amd/gtk/initrd.gz --- quiet
label rescue
    kernel /install.amd/vmlinuz
    append vga=788 initrd=/install.amd/gtk/initrd.gz rescue/enable=true --- quiet
EOF
cat > "$STAGE/isolinux/deploy.msg" <<'EOF'
Debian deploy installer

  deploy   Deploy install (ERASES the disk you pick)   [default, 10 s]
  serial   Deploy install on the serial console (ttyS0, 115200)
  stock    Stock Debian installer (graphical, no automation)
  rescue   Rescue mode

EOF

# The installer's "check the media" step compares against this
(cd "$STAGE" && find . -type f ! -name md5sum.txt ! -path './isolinux/*' -print0 \
    | xargs -0 md5sum > md5sum.txt)

# ----------------------------------------------------------------------------
# Repack with the original's boot setup (BIOS + UEFI, hybrid for USB)
# ----------------------------------------------------------------------------
# xorriso reports the options the stock ISO was made with; replaying them on
# the new tree keeps it bootable both ways and dd-able to a stick.
step "Writing $(basename "$OUT_ISO")"
rm -f "$OUT_ISO" "$STAGE/isolinux/boot.cat"
MKISOFS_OPTS="$(xorriso -indev /src.iso -report_el_torito as_mkisofs 2>/dev/null)"
eval "xorriso -as mkisofs -r $(echo "$MKISOFS_OPTS" | tr '\n' ' ') -o \"\$OUT_ISO\" \"\$STAGE\"" 2>&1 \
    | grep -vE '^xorriso : UPDATE' || true
[ -s "$OUT_ISO" ] || { echo "xorriso didn't write $OUT_ISO" >&2; exit 1; }
chmod 600 "$OUT_ISO"
rm -rf "$STAGE"

echo
echo "Built build/$(basename "$OUT_ISO") ($(du -h "$OUT_ISO" | cut -f1))"
echo "Write it to a stick (check the device first: this erases it):"
echo "  sudo dd if=build/$(basename "$OUT_ISO") of=/dev/sdX bs=4M conv=fsync status=progress"
