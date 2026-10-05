# Surface Pro 4 on CachyOS (Hyprland/Noctalia)

## What needs the Surface stack
On the stock CachyOS kernels the basics already work: WiFi (`mwifiex`), the
Surface buttons, lid wake, the system aggregator module and the camera drivers.

**Touchscreen and pen do not.** They need the `ipts` driver, which only ships in
the [linux-surface](https://github.com/linux-surface/linux-surface) kernel, plus
the `iptsd` daemon.

## Install
Run [`surface-setup.sh`](surface-setup.sh) (safe to re-run):
```bash
sudo bash ~/repo/Docs/cachyos/surface-setup.sh
```
It does the following:
1. Adds the linux-surface signing key (`56C464BAAC421453`) and the
   `[linux-surface]` repo to `/etc/pacman.conf`.
2. Installs `linux-surface`, `linux-surface-headers`, `iptsd`, `thermald` and
   `iio-sensor-proxy`.
3. Enables `thermald`. `iptsd` is started by udev, so there's nothing to enable.
4. Puts `*surface` first in `BOOT_ORDER` in `/etc/default/limine`, then runs
   `limine-update`. Limine boots the first entry, and `*` alone doesn't put
   linux-surface ahead of the CachyOS kernels, which stay as fallbacks.

Notes:
- **`libwacom-surface` no longer exists.** The linux-surface repo dropped it, and
  stock `libwacom` covers it.
- **linux-surface trails the CachyOS kernel** (6.19 vs 7.2 at install time) and is
  a plain Arch build, so you lose CachyOS's kernel tuning. That's the price of
  touch/pen.
- **If pacman asks for a provider** (e.g. `cairomm`), pick the `cachyos-extra-v3`
  build.

Check after a reboot:
```bash
uname -r                          # ...-surface
systemctl status 'iptsd@*'        # iptsd@dev-hidraw2 active (unless disabled, see below)
```

## Hyprland config (dotfiles)
Everything Surface-specific lives in the per-host override
`~/.config/hypr/config/host/surface.lua` (dotfiles branch `noctalia-cachyos`).
`hyprland.lua` requires it last, by kernel hostname.

It covers:
- **Auto-rotation.** It starts `~/.local/bin/hypr-autorotate`, which reads
  `monitor-sensor --accel` (iio-sensor-proxy) and rotates `eDP-1`, touch and pen
  through `hyprctl eval`. It keeps the current scale on each rotation.
- **Scale `1.266667`.** The shared config's `1.25` isn't a valid scale on the
  2736×1824 panel, so Hyprland complains and picks 1.27 itself.
- The Bluetooth auto-connect added by the auto-setup script.

Orientation mapping in `hypr-autorotate`: `normal→0, left-up→1, bottom-up→2,
right-up→3`. If a direction comes out wrong, swap 1 and 3.

## Touch calibration (iptsd)
iptsd only accepts a contact whose size and aspect fall within limits. A finger
partly off the screen edge reads as a narrow, elongated blob, and the default
`AspectMax = 2.5` rejects it. The result is a weak edge.

Calibrate by touching all over the screen for ~30 s, then pressing Ctrl+C:
```bash
cd /tmp && sudo iptsd-calibrate /dev/hidraw2   # writes 3 snippets to the current dir
```
- `2mm` is the recommended snippet; use `10mm` if iptsd misses inputs.
- Install the one you want as
  `/etc/iptsd.d/91-calibration-1B96-006A.conf` and restart iptsd.
- This machine measured size 0.9–6.0 and aspect 1.1–13.0 (defaults: 0.2–2.0 and
  1.0–2.5). The `10mm` snippet is installed.

To see the raw sensor heatmap (useful for finding dead areas):
```bash
sudo iptsd-show /dev/hidraw2
```

## Current state: touch and pen disabled
This digitizer has **multiple dead sections**. It could be panel failure (common
on the SP4) or a ribbon cable disturbed during the battery swap. The screen has
to come off for that swap, and the digitizer cables are fragile, so reseating them
is worth a try. On the SP4 the pen goes through the same digitizer, so it's
affected too.

Touch and pen are therefore disabled in iptsd. With both off, iptsd exits right
after starting.

`/etc/iptsd.d/99-disable.conf`:
```ini
[Touchscreen]
Disable = true

[Stylus]
Disable = true
```

**Re-enable** (e.g. after a digitizer fix):
```bash
sudo rm /etc/iptsd.d/99-disable.conf
sudo systemctl restart iptsd@dev-hidraw2
```
After a hardware fix, also recalibrate (above). The old calibration file is still
in `/etc/iptsd.d/`.

The on-screen keyboard (squeekboard) was removed along with touch. Its old setup
is in the dotfiles history (`surface: host config for the Surface Pro 4`).
Restoring it means:
- `squeekboard` in `surface-setup.sh`
- autostart lines in `surface.lua`
- `osk-toggle` (SUPER+K) and `osk-auto`, which turns off auto-show while the
  Type Cover (USB `045e:07e8`) is attached

## Open issue: blank login screen
Once, on the first linux-surface boot, the SDDM greeter started (logs show it on
VT2, Xorg up at 2736×1824) but nothing appeared on screen. Typing the password
blind worked. It's probably a race with Plymouth quitting at the same moment. If
it recurs, either make SDDM wait for `plymouth-quit` or drop `splash`.
