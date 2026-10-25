# FreeBSD deploy installer

> **Parked 2026-10-25.** The deployed boxes are going to Debian instead (see
> `../Debian`), mainly for Linux tooling and vendor software that only ships for
> glibc. This works up to a built image, but was never test-installed on
> hardware; `openItems.md` has where it stopped. The design carries over.

A USB stick that installs a standard FreeBSD box. You boot it and answer a
short interview, and it installs:

1. hostname
2. Wi-Fi: Personal (password), Enterprise (username + password), open, or none,
   and then DHCP or a static IP
3. each wired port: unused, a static IP (shop-floor LANs), or DHCP. The menu
   shows each port's MAC and whether a cable is in.
4. gateway and DNS, asked only when nothing uses DHCP
5. target disk, then a summary and a last-chance confirmation

The result has:

- a standard **root** password and a standard **user** (`angstrom`, in
  `wheel`, zsh + Oh My Zsh + Starship) with a standard password
- **SSH** on, with our keys authorized for both accounts
- the network as answered (DHCP on every port if nothing was chosen)
- on first boot, `provision.sh` runs once: it installs packages and the firmware
  this hardware needs, sets sudo, the sshd policy, video + serial consoles (for
  monitor / IPKVM / headless) and security patches

Parked decisions and later work are tracked in [`openItems.md`](openItems.md).

`provision.sh` also runs on its own, so a box installed by hand can be brought
up to the same standard.

Target: **FreeBSD 15.1-RELEASE amd64** (`FreeBSD-15.1-RELEASE-amd64-memstick.img`).

## Files

| File | What it is |
|---|---|
| `deploy.conf` | The standard settings: user, timezone, ZFS/UFS, swap, SSH root policy, serial console. Not secret. |
| `packages.txt` | Packages every box gets. |
| `make-secrets.sh` | Prompts for the root and user passwords, writes their hashes and your SSH public key(s) to `secrets.conf`. |
| `secrets.conf` | **Gitignored.** This repo is public, so the password hashes stay off GitHub. |
| `build-image.sh` | Runs on FreeBSD as root. Copies the memstick image and adds our `/etc/installerconfig` to it. |
| `installer/preamble.sh` | Installer half 1: the questions (runs before the disk is touched). |
| `installer/setup.sh` | Installer half 2: runs chrooted into the new system. Sets hostname, accounts, keys, and arms first boot. |
| `firstboot/deploy_firstboot` | rc.d script that runs `provision.sh` once, on first boot. |
| `provision.sh` | Brings a box up to the standard config. Safe to re-run. |
| `openItems.md` | Open decisions and parked work (Secure Boot, GUI, hardening...). |

## How it works

When the stock FreeBSD installer finds `/etc/installerconfig` on its boot
media, it runs `bsdinstall script` on that file instead of showing its menus.
The file has two halves, split at the first `#!` line:

1. **Preamble.** This is sourced in the installer before partitioning. It holds
   `deploy.conf` and `installer/preamble.sh`, which asks the questions and sets
   `ZFSBOOT_*` / `PARTITIONS`, plus `COMPONENTS=base` for a pkgbase install.
2. **Setup.** This runs chrooted into the new system once base is installed.
   `build-image.sh` copies `provision.sh`, the config files and the rc script
   into this half as here-docs, followed by `installer/setup.sh`.

**No network needed.** The install comes entirely off the stick, from two
offline package repos:

- `/usr/freebsd-packages/offline`: base and kernel as pkgbase packages. This
  ships on the stock 15.x memstick.
- `/usr/freebsd-packages/deploy`: `packages.txt` plus all Wi-Fi and GPU
  firmware. `build-image.sh` adds this one.

The chroot can't see the stick, so the preamble wraps `bsdinstall` in a shell
function that nullfs-mounts the deploy repo into the new system before the
chroot runs and unmounts it after. `setup.sh` installs `packages.txt` and
whatever firmware `fwget` matches to this box's PCI IDs.

`setup.sh` then writes `/firstboot`, which makes rc run `deploy_firstboot` →
`provision.sh` once at first boot. Without internet (a box on isolated LANs
only) it skips package updates and patches and still applies the config. If
`pkg upgrade` installed a new kernel, the box reboots into it before the login
prompt.

The installed system's package repos point online (pkg.FreeBSD.org), so
`pkg upgrade` patches base and packages together from then on.

The first menu also offers the **stock installer** or a **shell**, so the same
stick still works for a one-off manual install.

## Building the stick

On a FreeBSD 15 amd64 box, as root, with internet. The memstick's root is UFS,
which Linux can't safely write, and the deploy repo is fetched for the build
box's own package ABI. The image grows by the repo's size, about 1 GB. Any
stick of 4 GB or more is plenty.

```sh
./make-secrets.sh                     # once; or: ./make-secrets.sh key1.pub key2.pub
./build-image.sh ~/FreeBSD-15.1-RELEASE-amd64-memstick.img
# -> build/FreeBSD-15.1-RELEASE-amd64-deploy.img
```

`make-secrets.sh` works on Linux too, so you can run it there and copy
`secrets.conf` across with the folder.

Write the image to a stick. **Check the device name first, because this erases
it:**

```sh
dd if=build/FreeBSD-15.1-RELEASE-amd64-deploy.img of=/dev/daX bs=1m conv=sync status=progress   # FreeBSD
sudo dd if=build/FreeBSD-15.1-RELEASE-amd64-deploy.img of=/dev/sdX bs=1M conv=fsync status=progress  # Linux
```

`build/` holds the generated `installerconfig` (handy for review) and the
image. Both contain the password hashes, and both are gitignored.

## Provisioning an existing box

```sh
scp -r FreeBSD steve@host:
ssh steve@host
su -    # or sudo, once provisioned
sh ~steve/FreeBSD/provision.sh
```

## Notes

- **Root over SSH** is `prohibit-password` by default: key only. The standard
  root password works at the console / IPKVM and via `su`. Change
  `SSH_PERMIT_ROOT_LOGIN` in `deploy.conf` if a box needs it.
- **Consoles.** Video stays primary, so a monitor or IPKVM sees everything.
  Serial (`ttyu0`, 115200) is added as a second console for headless boxes.
  Turn this off with `SERIAL_CONSOLE="no"`.
- **ZFS boots BIOS+UEFI** (`ZFSBOOT_BOOT_TYPE`), so a disk boots whichever way
  the firmware is set.
- The installer screens show on the **primary console only**. Other consoles
  get a "use the primary console" message.

