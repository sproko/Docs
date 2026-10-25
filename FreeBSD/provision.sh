#!/bin/sh
# Bring a FreeBSD box up to the standard deployed config. Idempotent: safe to
# re-run, and runs the same whether the box came from the deploy USB (where it
# runs once at first boot as /usr/local/sbin/deploy-provision) or was installed
# by hand.
#
# On a hand-installed box, run it from a checkout of this folder, as root:
#   sh provision.sh
#
# Reads deploy.conf and packages.txt from beside this script, falling back to
# the copies the installer put in /usr/local/etc.

set -eu

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

find_config() {
    for f in "$SCRIPT_DIR/$1" "/usr/local/etc/$2"; do
        [ -f "$f" ] && { echo "$f"; return; }
    done
    echo "Can't find $1 (looked beside this script and in /usr/local/etc)" >&2
    exit 1
}

[ "$(id -u)" -eq 0 ] || { echo "Run as root." >&2; exit 1; }
[ "$(uname -s)" = "FreeBSD" ] || { echo "This is for FreeBSD." >&2; exit 1; }

. "$(find_config deploy.conf deploy.conf)"
PACKAGES_FILE="$(find_config packages.txt deploy-packages.txt)"

step() { echo; echo "==> $*"; }

# ============================================================================
# STEP 1: Packages
# ============================================================================
step "Packages"
# A box on isolated LANs has no way to the package repos. The deploy stick
# already installed packages.txt and its firmware, so carry on with the config
# steps rather than failing the whole run.
export ASSUME_ALWAYS_YES=yes
ONLINE=""
if { pkg -N >/dev/null 2>&1 || pkg bootstrap -f; } && pkg update; then
    ONLINE=yes
    # shellcheck disable=SC2046
    pkg install $(grep -vE '^[[:space:]]*(#|$)' "$PACKAGES_FILE")

    # Firmware for whatever this box has (GPU, Wi-Fi...), matched from its PCI
    # IDs the same way the interactive installer's firmware step does it.
    step "Firmware for this hardware"
    fwget
else
    echo "Package repos unreachable: skipping installs, firmware and patches."
fi

# ============================================================================
# STEP 2: sudo for wheel
# ============================================================================
if [ -x /usr/local/bin/sudo ]; then
    step "sudo for wheel"
    sudoers_drop=/usr/local/etc/sudoers.d/wheel
    echo '%wheel ALL=(ALL:ALL) ALL' > "$sudoers_drop.tmp"
    chmod 440 "$sudoers_drop.tmp"
    visudo -cqf "$sudoers_drop.tmp"
    mv "$sudoers_drop.tmp" "$sudoers_drop"
fi

# ============================================================================
# STEP 3: Login shell and wheel for the standard user
# ============================================================================
# Skipped when the user doesn't exist yet (a hand-installed box): create it
# first, as in README.md.
if pw usershow "$DEPLOY_USER" >/dev/null 2>&1; then
    step "Login shell for $DEPLOY_USER"
    if ! grep -qx "$DEPLOY_USER_SHELL" /etc/shells; then
        echo "$DEPLOY_USER_SHELL isn't in /etc/shells; is it in packages.txt?" >&2
        exit 1
    fi
    pw usermod "$DEPLOY_USER" -s "$DEPLOY_USER_SHELL"
    # The installer adds it to wheel; an account made by hand may not be
    pw groupmod wheel -m "$DEPLOY_USER"

    # Mirrors the CachyOS ~/.zshrc, but on the ohmyzsh package's shared copy,
    # which pkg upgrade keeps current. Only written if missing, so it's never
    # clobbered; that also stops zsh's new-user menu at first login.
    user_home="$(pw usershow "$DEPLOY_USER" | cut -d: -f9)"
    if [ "${DEPLOY_USER_SHELL##*/}" = "zsh" ] && [ ! -e "$user_home/.zshrc" ]; then
        cat > "$user_home/.zshrc" <<'EOF'
# Written by provision.sh; edit freely, it won't be overwritten.
export ZSH=/usr/local/share/ohmyzsh
# $ZSH is root-owned, so the cache lives with the user
ZSH_CACHE_DIR="$HOME/.cache/oh-my-zsh"
# The package drops omz's updater; pkg upgrade updates it instead
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
    echo "No $DEPLOY_USER account yet; skipping its login shell."
fi

# ============================================================================
# STEP 4: sshd policy
# ============================================================================
# sshd keeps the FIRST value it reads for each option, so a managed block at
# the top of sshd_config overrides the stock defaults below it without editing
# them. Re-runs replace the block.
step "sshd"
SSHD_CONFIG=/etc/ssh/sshd_config
BLOCK_BEGIN="# BEGIN deploy-provision (managed by provision.sh; edits here are overwritten)"
BLOCK_END="# END deploy-provision"
tmp="$(mktemp)"
{
    echo "$BLOCK_BEGIN"
    echo "PermitRootLogin $SSH_PERMIT_ROOT_LOGIN"
    echo "UseDNS no"
    echo "$BLOCK_END"
    awk -v b="$BLOCK_BEGIN" -v e="$BLOCK_END" \
        '$0 == b {skip=1} !skip {print} $0 == e {skip=0}' "$SSHD_CONFIG"
} > "$tmp"
sshd -t -f "$tmp"
cat "$tmp" > "$SSHD_CONFIG"
rm -f "$tmp"
sysrc sshd_enable="YES"
if service sshd status >/dev/null 2>&1; then
    service sshd reload
fi

# ============================================================================
# STEP 5: Services and base settings
# ============================================================================
step "Services"
sysrc ntpd_enable="YES" ntpd_sync_on_start="YES"
sysrc dumpdev="AUTO"
sysrc clear_tmp_enable="YES"

# ============================================================================
# STEP 6: Post-mortem records
# ============================================================================
# For working out why a box died or restarted. A panic is covered by the
# dumpdev above plus gdb (crashinfo needs it for the backtrace). Accounting
# logs every process that exits; periodic(8) rotates it daily, keeping 3.
step "Post-mortem records"
sysrc accounting_enable="YES"
service accounting start
# What used the memory, every 5 minutes: top's header has free RAM and the ZFS
# ARC, then the 15 largest processes with their swap (-w) and full command line
# (-a), which tells apart instances of the same program. Lines are cut at 400
# characters so one huge command line can't bloat it.
#
# Normally about 700 KB a day. newsyslog rotates at midnight or at 2 MB,
# whichever comes first, and keeps 14 bzip2'd files, so it never passes ~5 MB.
mkdir -p /usr/local/etc/cron.d /usr/local/etc/newsyslog.conf.d
echo '*/5 * * * * root (echo "=== $(date -Iminutes)"; /usr/bin/top -b -a -w -o res 15 | cut -c1-400; echo) >> /var/log/topsnap.log 2>&1' \
    > /usr/local/etc/cron.d/deploy-topsnap
echo '/var/log/topsnap.log root:wheel 640 14 2048 @T00 JC' \
    > /usr/local/etc/newsyslog.conf.d/deploy-topsnap.conf
# memhog answers "what peaked, and when?" from that log after an incident
cat > /usr/local/sbin/memhog <<'MEMHOG_EOF'
#!/bin/sh
# Which processes peaked in memory, from the snapshots in /var/log/topsnap.log
# (and its rotated .bz2 copies). Each process is shown once, at its own peak
# RAM + swap, with when that was and its full command line.
#
#   memhog [YYYYMMDD] [from HH:MM] [to HH:MM] [count]
#   memhog                      # today, top 10
#   memhog 20261025 09:00 12:30 # that morning
#
# Only the 15 largest processes are logged per snapshot; a leak gets there
# well before it matters.

set -eu
LOG="${TOPSNAP_LOG:-/var/log/topsnap.log}"

day="$(date +%Y%m%d)"
case "${1:-}" in [0-9][0-9][0-9][0-9][0-9][0-9][0-9][0-9]) day="$1"; shift ;; esac
from="${1:-00:00}" to="${2:-23:59}" count="${3:-10}"
day="$(echo "$day" | sed -E 's/(....)(..)(..)/\1-\2-\3/')"
tab="$(printf '\t')"

for f in "$LOG".*.bz2 "$LOG"; do
    [ -f "$f" ] || continue
    case "$f" in
        *.bz2) bzcat "$f" ;;
        *) cat "$f" ;;
    esac
done | awk -v day="$day" -v from="$from" -v to="$to" '
    # top prints sizes as 3324K, 14M, 1G, 0B; work in KB
    function kb(v,  n, u) {
        n = v + 0; u = substr(v, length(v))
        if (u == "B") return n / 1024
        if (u == "M") return n * 1024
        if (u == "G") return n * 1048576
        if (u == "T") return n * 1073741824
        return n
    }
    function mb(k) { return sprintf("%.0fM", k / 1024) }
    /^=== / {
        ts = $2; hm = substr(ts, 12, 5)
        on = substr(ts, 1, 10) == day && hm >= from && hm <= to
        next
    }
    !on || $1 !~ /^[0-9]+$/ || NF < 12 { next }
    {
        # COMMAND starts after WCPU, the first field ending in "%". Counting
        # from there copes with top dropping the C column on one-CPU boxes.
        for (i = 9; i <= NF && $i !~ /%$/; i++) ;
        cmd = $(i + 1); for (j = i + 2; j <= NF; j++) cmd = cmd " " $j
        res = kb($7); swp = kb($8); key = $1 SUBSEP cmd
        if (!(key in peak) || res + swp > peak[key]) {
            peak[key] = res + swp
            line[key] = sprintf("%7s %7s %7s  %s  %6s  %s", mb(res + swp), mb(res), mb(swp), hm, $1, cmd)
        }
    }
    END { for (k in peak) printf "%d\t%s\n", peak[k], line[k] }
' | sort -t "$tab" -k1,1nr | head -n "$count" | cut -f2- \
  | { printf '%7s %7s %7s  %s  %6s  %s\n' PEAK RES SWAP WHEN PID COMMAND; cat; }
MEMHOG_EOF
chmod 755 /usr/local/sbin/memhog

# ============================================================================
# STEP 7: ZFS cache cap
# ============================================================================
# Uncapped, the ARC grows into nearly all free RAM. It does give it back, but
# not fast enough for a box that also runs Postgres and NATS, and Postgres
# would end up caching the same pages twice. sysctl.conf, not loader.conf:
# it's a runtime tunable (and sysrc rejects dotted names).
if kldstat -q -m zfs; then
    step "ZFS cache cap"
    arc_max=$(( $(sysctl -n hw.physmem) * ${ARC_MAX_PERCENT:-25} / 100 ))
    touch /etc/sysctl.conf
    sed -i '' '/^vfs\.zfs\.arc\.max=/d' /etc/sysctl.conf
    echo "vfs.zfs.arc.max=$arc_max" >> /etc/sysctl.conf
    sysctl vfs.zfs.arc.max="$arc_max"
fi

# ============================================================================
# STEP 8: Consoles (monitor / IPKVM / serial)
# ============================================================================
# Takes effect next boot. Video stays primary so a monitor or IPKVM shows the
# loader and kernel output; serial is added alongside, and /etc/ttys already
# runs a getty on ttyu0 whenever it's a console ("onifconsole").
step "Consoles"
LOADER_CONF=/boot/loader.conf
sysrc -f "$LOADER_CONF" autoboot_delay="5"
if [ "$SERIAL_CONSOLE" = "yes" ]; then
    if [ "$(sysctl -n machdep.bootmethod)" = "UEFI" ]; then
        video_console="efi"
    else
        video_console="vidconsole"
    fi
    sysrc -f "$LOADER_CONF" boot_multicons="YES"
    sysrc -f "$LOADER_CONF" console="$video_console,comconsole"
    sysrc -f "$LOADER_CONF" comconsole_speed="115200"
else
    sysrc -f "$LOADER_CONF" -x boot_multicons console comconsole_speed 2>/dev/null || true
fi

# ============================================================================
# STEP 9: Security patches
# ============================================================================
# A pkgbase system (base installed as FreeBSD-* packages) is patched with
# `pkg upgrade`; freebsd-update refuses to run on one.
if [ "$RUN_FREEBSD_UPDATE" = "yes" ] && [ -n "$ONLINE" ]; then
    step "Security patches"
    if pkg which -q /bin/sh >/dev/null 2>&1; then
        echo "pkgbase system: patching with pkg upgrade"
        pkg upgrade
    else
        PAGER=cat freebsd-update --not-running-from-cron fetch
        # Exits 2 when there's nothing to install
        PAGER=cat freebsd-update --not-running-from-cron install || [ $? -eq 2 ]
    fi
fi

# ============================================================================
# DONE
# ============================================================================
echo
echo "Provisioned $(hostname) ($(freebsd-version -u), kernel $(freebsd-version -k))"
if [ "$(freebsd-version -k)" != "$(uname -r)" ]; then
    echo "A new kernel is installed: reboot to run it."
fi
