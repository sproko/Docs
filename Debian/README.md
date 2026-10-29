# Debian deploy installer

A USB stick that installs a standard Debian 13 shop-floor box with no network
needed. Boot it, pick the disk, and walk away; on first boot a short dialog on
the console sets the box's name and network.

**The installer asks one thing:** which disk to install to (the stick itself is
listed too; it's the small one). It then erases that disk and installs without
further questions, then reboots.

**The first-boot dialog** (on the monitor or IPKVM) asks:

1. hostname
2. Wi-Fi, if the box has it: Personal (password), Enterprise (username +
   password, PEAP), open, or none, and then DHCP or a static IP
3. each wired port: unused, a static IP (shop-floor LANs), or DHCP. The menu
   shows each port's model, MAC, and whether a cable is in.
4. gateway and DNS, asked only when nothing uses DHCP
5. a summary to confirm

Answer "No" at the first screen, or leave nobody at the console, and every
wired port runs DHCP, so the box is still reachable over SSH. Run
`sudo deploy-netconfig` any time to redo it (from the console: applying it over
SSH can cut your own session).

## What you get

- Debian 13 on LVM + ext4: `/` 20 GiB, swap 4 GiB, `/srv` 30 GiB for service
  data, and the rest of the disk free in the volume group (`vg0`) to grow any
  of them later with `lvextend -r`.
- root with the standard password (console only; SSH as root is key-only).
- `angstrom` with the standard password, in `sudo`, on zsh with Oh My Zsh (and
  Starship over SSH), with the SSH keys from `secrets.conf`.
- Claude Code (`claude`, the CLI) from Anthropic's signed apt repo, on the
  `latest` channel (`CLAUDE_CODE_CHANNEL` in `deploy.conf`). apt updates it
  nightly along with the security updates.
- Neovim with LazyVim for `angstrom` (the stock starter plus the markdown
  extra), ready offline: plugins, treesitter parsers and Mason tools are built
  onto the stick. gcc stays on the box so LazyVim can keep itself current.
- herdr (herdr.dev).
- Neovim, tree-sitter and herdr come from their GitHub releases, since Debian's
  are too old or missing: the newest when the stick was built, moved to the
  newest again whenever `bootstrap.sh` runs online. No Go or .NET toolchains.
- NetworkManager on every port; technicians can use `nmtui` or rerun
  `deploy-netconfig`.
- Consoles on video and on the first serial port (115200), for GRUB, the
  kernel and a login.
- Security updates installed automatically (unattended-upgrades; never
  reboots on its own).
- Firmware for the usual Wi-Fi, NIC and GPU parts, plus CPU microcode.
- Post-mortem records for "why did it die or restart?":

  | Question | Where |
  |---|---|
  | What happened before the last boot? | `journalctl -b -1` (journal kept across reboots, 200 MB max) |
  | Did the kernel crash? | `/var/crash` (kdump; reserves 192 MB of RAM) |
  | What was eating memory? | `memhog [YYYYMMDD] [from HH:MM] [to HH:MM]`, from atop's 10-minute history (14 days kept) |
  | What had just run? | `lastcomm` (process accounting) |

No GUI, and no Docker: services (NATS, Postgres, our own) install natively
through their own deploy scripts, which put their data under `/srv`.

## Files

| File | What it is |
|---|---|
| `deploy.conf` | Standard settings (user, sizes, consoles...). No secrets. |
| `packages.txt` | Packages every box gets. |
| `make-secrets.sh` | Asks for the root + `angstrom` passwords, writes `secrets.conf` (hashes + SSH keys; gitignored). |
| `build-iso.sh` | Builds the stick image from the stock netinst ISO. |
| `installer/preseed.cfg` | Answers for the Debian installer (template; `build-iso.sh` fills it in). |
| `installer/late.sh` | Runs at the end of the install: copies everything in, runs `bootstrap.sh` offline. |
| `bootstrap.sh` | The standard config. Idempotent; runs at install, again at first boot (online: updates), and by hand. |
| `firstboot/` | The first-boot service and the network dialog (`deploy-netconfig`). |
| `tools/memhog` | Biggest memory users from atop's history. |
| `tools/fetch-upstream`, `tools/install-upstream` | Download the newest Neovim, tree-sitter and herdr (checked against GitHub's SHA-256), and install them. |
| `tools/lazyvim-setup` | Sets up LazyVim for the user running it: the starter plus `nvim/`, then plugins, parsers and Mason tools. |
| `nvim/` | Our changes on top of the LazyVim starter. |
| `keys/claude-code.asc` | Anthropic's signing key for the claude-code apt repo (fingerprint `31DDDE24DDFAB679F42D7BD2BAA929FF1A7ECACE`). |
| `openItems.md` | Parked decisions and known gaps. |

On an installed box all of this lives in `/usr/local/share/deploy`, with
`deploy-bootstrap` and `deploy-netconfig` in `/usr/local/sbin`.

## How it works

- **Offline:** `build-iso.sh` downloads `packages.txt` and every dependency
  (resolved against an empty system, so nothing is assumed installed) into a
  small apt repo on the stick (claude-code included, from Anthropic's repo),
  plus a pinned Oh My Zsh, the upstream tools, and a prebuilt LazyVim. The installer runs with
  networking off; `late.sh` mounts that repo into the new system and
  `bootstrap.sh` installs from it.
- **The preseed lives in the installer's initrd**, so even the language and
  keyboard questions are answered.
- **Boot menu:** the deploy install is the default after 10 seconds. There's
  also a serial-console variant, the stock graphical installer (no automation),
  and rescue mode. Boots on UEFI (tested) and BIOS (not yet
  tested).
- **First boot** (`deploy-firstboot.service`) runs the dialog on tty2 before
  the login prompt, then reruns `bootstrap.sh`, which installs updates when the
  box can reach Debian's mirrors, and reboots if a new kernel came in.

## Building the stick

Needs Docker and internet (the work runs in a `debian:trixie` container). On
the CachyOS workstation:

```sh
./make-secrets.sh            # once; or copy secrets.conf from ../FreeBSD
./build-iso.sh ~/Downloads/debian-13.7.0-amd64-netinst.iso
lsblk                        # find the stick
sudo dd if=build/debian-13.7.0-amd64-deploy.iso of=/dev/sdX bs=4M conv=fsync status=progress
```

The image is about 1.2 GB. Rebuild it when `packages.txt` changes, or every so
often so installs start closer to current (first boot patches them anyway).

## Re-applying the standard to an existing box

```sh
sudo /usr/local/share/deploy/bootstrap.sh          # a box from this stick
sudo sh bootstrap.sh                               # any Debian 13 box, from a checkout
```

A box not installed from the stick needs the `angstrom` account first, and
Oh My Zsh, the upstream tools and LazyVim are downloaded instead of coming
from the stick.

## Testing in a VM

The install was tested in QEMU (UEFI, 4 GB, NVMe, the ISO attached as a USB
stick, two NICs): disk question, unattended install, first-boot dialog with
DHCP + static ports, SSH as `angstrom` with the key, updates on first boot.
Not yet tested: real hardware, Wi-Fi, BIOS boot.
