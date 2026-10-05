#!/bin/bash
# Surface Pro 4 setup for CachyOS
#
# linux-surface kernel (touchscreen/pen need its ipts driver — stock CachyOS
# kernels don't have it), iptsd, thermald, plus the packages the per-host hypr
# config (dotfiles: .config/hypr/config/host/surface.lua) expects:
# iio-sensor-proxy for auto-rotation and squeekboard for the on-screen keyboard.
#
# libwacom-surface is gone from the linux-surface repo; stock libwacom covers it.
#
#   sudo bash surface-setup.sh
#
# Safe to re-run: every step is idempotent.
set -euo pipefail

# 1. linux-surface signing key
curl -fsSL https://raw.githubusercontent.com/linux-surface/linux-surface/master/pkg/keys/surface.asc \
  | pacman-key --add -
pacman-key --finger 56C464BAAC421453
pacman-key --lsign-key 56C464BAAC421453

# 2. linux-surface repo
if ! grep -q '^\[linux-surface\]' /etc/pacman.conf; then
  printf '\n[linux-surface]\nServer = https://pkg.surfacelinux.com/arch/\n' >> /etc/pacman.conf
fi

# 3. Packages (iptsd is started automatically by udev)
pacman -Syu --needed linux-surface linux-surface-headers iptsd thermald \
  iio-sensor-proxy squeekboard

# 4. Thermal management
systemctl enable --now thermald

# 5. Boot linux-surface by default — Limine boots the first entry, and "*"
#    alone doesn't put it ahead of the CachyOS kernels (kept as fallbacks)
if ! grep -q '^BOOT_ORDER="\*surface' /etc/default/limine; then
  sed -i 's/^BOOT_ORDER="/BOOT_ORDER="*surface, /' /etc/default/limine
fi
limine-update

echo
echo "Done. Reboot — Limine should come up on linux-surface."
