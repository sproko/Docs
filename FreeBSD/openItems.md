# Open items

Decisions and work parked for later. Move an item to **Done** with a line on
what was decided, rather than deleting it.

## Open

- **Secure Boot.** FreeBSD has no Microsoft-signed bootloader, so the only
  route is our own keys:
  - Sign `loader.efi` with `uefisign` (it ships with FreeBSD).
  - Enroll our certificate in each box's BIOS by hand. These are Lenovo boxes
    (PCI subvendor `17aa`), and their BIOS can enroll custom keys.
  - Re-sign the ESP copy after every bootloader update, i.e. a `pkg upgrade`
    that touches `FreeBSD-bootloader`. Provisioning would need to automate that.

  It verifies only the loader, not the kernel or its modules, so it's mostly a
  compliance checkbox. Skipped for now (2026-10-24).
- **WPA2-Enterprise without a CA certificate.** The installer writes PEAP
  configs without `ca_cert`, so the box doesn't verify the RADIUS server. Get
  the company CA from IT and pin it.
- **Wi-Fi password on disk.** `/etc/wpa_supplicant.conf` holds it in plain
  text (mode 600, root only). That's normal for wpa_supplicant; noted so it's a
  conscious choice.
- **GUI**: whether deployed boxes get one, and which.
- **Hardening**: sysctls (`security.bsd.*`), `securelevel`, a `pf` firewall,
  especially between the company Wi-Fi and the shop-floor LANs.
- **Service stack (NATS, Postgres)**: native packages plus the official NATS
  binary, not Docker, which on FreeBSD would mean a Linux VM costing about a
  third of a 4 GB box. Installing and configuring them, and our own services,
  belongs to their deploy scripts, which need a network path to the box, so
  no offline config on the stick. Still open: where those scripts live
  (aelab-stack grows a FreeBSD target?), ZFS datasets for their data
  (`recordsize=16k`, `primarycache=metadata` for Postgres), and memory
  settings sized for 4 GB.
- **IPv6**: the hand-installed box takes router advertisements on `re0`; the
  installer doesn't configure IPv6 yet.
- **The `steve` account on `freebsd`** exists only so Claude can SSH in. It
  isn't part of the standard. Remove it when the prototype work is done, along
  with its temporary passwordless sudo:
  `rm /usr/local/etc/sudoers.d/zz-steve-temp`. The `zz-` prefix matters: sudo
  applies the last matching rule, and the `wheel` drop-in, which requires a
  password, would otherwise sort after it and win.
- **Offline installs start unpatched.** The stock stick's base repo is
  15.1-RELEASE as shipped (no `-pN` patches). First boot patches it with
  `pkg upgrade` when it has internet. A box with no internet stays at
  15.1-RELEASE until it gets online.
- **Untested on hardware**: the installer interview (especially the Wi-Fi
  scan's SSID parsing), the `bsdinstall` wrapper that mounts the deploy repo,
  and growing the memstick image in `build-image.sh`.
- **Stick freshness**: the deploy repo is a snapshot from build day. Rebuild
  the stick after a FreeBSD minor release (the firmware kmods are tied to it)
  or when `packages.txt` changes.

## Done

- **Standard user is `angstrom`**: in `wheel`, zsh + Oh My Zsh + Starship (2026-10-24).
- **Base system via pkgbase**: patched with `pkg upgrade`, not `freebsd-update`
  (2026-10-24).
- **Firmware**: `fwget` installs whatever the hardware needs (2026-10-24).
- **Offline install**: the stick carries base (stock) plus a "deploy" repo with
  `packages.txt` and all Wi-Fi + GPU firmware, so no network is needed
  (2026-10-24).
- **Shop-floor LANs use static IPs**: devices are set up to talk to specific
  addresses (2026-10-24).
- **Post-mortem records**: crash dumps + `gdb` for crashinfo backtraces,
  process accounting (`lastcomm`), and a `top` snapshot every 5 minutes in
  `/var/log/topsnap.log` (full command lines and swap per process), rotated at
  midnight or 2 MB and kept 14 files, so ~5 MB at most. `memhog` reads it back:
  each process at its peak, with when and its command line (2026-10-25).
- **ZFS ARC cap**: `provision.sh` sets `vfs.zfs.arc.max` in `/etc/sysctl.conf`
  to `ARC_MAX_PERCENT` (25%) of RAM, so 1 GB on a 4 GB box (2026-10-25).
