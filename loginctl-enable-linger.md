# `loginctl enable-linger` — keeping user services alive after logout

## Mental model

Every user has a systemd **user manager** (`user@<uid>.service`). By default it
**starts when you log in and stops when your last session ends**. On logout,
systemd tears down the user manager and — depending on the `KillUserProcesses`
policy in `logind.conf` — sweeps your user processes.

**Lingering** tells systemd to keep your user instance running **even with no
active login session**, and to **start it at boot** (before you log in). So your
`systemctl --user` services run unattended, surviving logout and reboots.

## Commands

```bash
loginctl enable-linger $USER          # turn on (may need sudo for another user)
loginctl show-user $USER -p Linger    # check -> Linger=yes/no
loginctl disable-linger $USER         # turn off
ls /var/lib/systemd/linger/           # lingering users are flagged here
```

## The common misconception

"Enable-linger makes tmux survive logout" is only half true:

- Linger keeps the *user manager* alive, but a `tmux` launched straight from a
  terminal lives in that login's **session scope**, which is still cleaned up on
  logout.
- To make something genuinely persist, run it **under the user manager**, not the
  session scope:

  ```bash
  systemd-run --user --scope tmux new-session -d   # detached from session scope
  # or better: make it a proper  systemctl --user  service
  ```

  Linger is what lets *those* keep running while you're logged out.

## When you actually want it

- A **self-hosted CI runner**, background sync, or build agent you want up 24/7
  without staying logged in → enable linger + run it as a `--user` service.
- **VMs in libvirt _session_ mode** (`qemu:///session`) — they're tied to your
  user manager and die on logout **without** linger.
- Keeps a systemd **ssh-agent** user socket warm across logout (minor).

## When you DON'T need it

- **libvirt _system_ mode** (`qemu:///system`) — VMs run under the **system**
  libvirtd, independent of your login session, so they already survive
  logout/reboot (with `pool-autostart` / `net-autostart`). Linger is irrelevant.
  *(This is the setup on the CachyOS dev tower — see `setup-libvirt.sh`.)*

## Trade-off

Enabling it means those user services **run at boot and consume resources even
when nobody is logged in**, and start without your interactive environment
(different env, no display, etc.). Great for daemons; unnecessary if you just log
in normally and your long-running things (like system-mode VMs) aren't tied to
your session.

## TL;DR

Reach for `enable-linger` only when you want a **user-level** service alive while
logged out. If your persistent workload is a **system** service (like system-mode
libvirt VMs), it's already independent of your login — no linger needed.
