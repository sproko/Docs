# Open items

Decisions and work parked for later. Move an item to **Done** with a line on
what was decided, rather than deleting it.

## Open

- **Test on real hardware**: the M90n (`freebsd`, to be reinstalled as the
  prototype). Still untested anywhere: Wi-Fi (scan, PSK, PEAP), BIOS boot,
  serial console on a real port.
- **WPA2-Enterprise without a CA certificate.** The dialog sets up PEAP without
  one, so the box doesn't verify the RADIUS server. Get the company CA from IT
  and pin it (`802-1x.ca-cert`).
- **Wi-Fi password on disk**, in `/etc/NetworkManager/system-connections`
  (root only). Normal for NetworkManager; noted so it's a conscious choice.
- **Hardening**: a firewall (nftables), especially between the company Wi-Fi
  and the shop-floor LANs; sysctls.
- **Services**: NATS, Postgres and our own install natively through their own
  deploy scripts (out of scope here). They should keep their data under `/srv`
  (Postgres `data_directory`, NATS `store_dir`), and be sized for 4 GB boxes.
- **What the base box provides for the apps' deployments** (2026-10-25). Two
  apps are being built in other sessions: the PM system, and a full PVD
  simulator including its HMI. Each has a handful of things that would make
  its deployment easier if the base box already had them. To do: collect
  those lists from those sessions, then decide per item whether it goes on
  the stick or stays in the app's deploy script. Candidates so far:
  - NATS at a pinned version (single program, like herdr), with its service
    unit and `/srv` store, and where its configuration comes from;
  - Postgres at a pinned major version (PGDG's apt repo, e.g. `postgresql-17`)
    with its data in `/srv`;
  - whatever service user, folders and systemd conventions the apps share.

  Check how the HMI displays before deciding: the box has no GUI, so a
  browser-based HMI fits as is, while a native desktop one would need a
  display stack.
- **Secure Boot** should just work (Debian's shim is Microsoft-signed), but
  hasn't been tried with it on.
- **IPv6**: static ports have it off; DHCP ports take router advertisements.
- **Console noise**: `systemd-ssh-generator: Failed to query local AF_VSOCK
  CID` prints on every systemd reload in the VM. Harmless; check whether real
  hardware does it too.
- **Stick freshness**: the offline repo is a snapshot from build day. Rebuild
  after a Debian point release or when `packages.txt` changes.

## Done

- **Debian instead of FreeBSD** (2026-10-25): Linux tooling, glibc-only vendor
  software, Claude Code. The FreeBSD version is parked in `../FreeBSD`.
- **No Docker** (2026-10-25): services run natively; saves memory on 4 GB boxes
  and avoids Docker's firewall bypass.
- **No GUI** (2026-10-25).
- **LVM + ext4** with free space left in the VG (from aelab-stack's item 9).
- **Network setup at first boot**, not in the installer: the installer can only
  configure one interface, and this way it can be rerun (`deploy-netconfig`).
- **Post-mortem records**: persistent journal, kdump, atop + `memhog`, acct.
