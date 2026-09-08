#!/bin/bash
# CachyOS Post-Setup — finish the bits that need a reboot, then verify the box
#
# Run AFTER cachyos-auto-setup.sh and a reboot. Two phases:
#   ACTIONS  — the few things left that can be done non-interactively
#   CHECKS   — assert the machine actually ended up how it was meant to
#
# Every check here exists because something failed silently on a real setup:
# gh logged into the wrong account per directory, a .NET path hardcoded to
# another box's home, noctalia settings renamed by a version bump, a generated
# theme file fighting the dotfiles copy. None of it surfaced on its own.
#
# Safe to re-run any time as a health check — the actions are idempotent.
#
#   chmod +x cachyos-post-setup.sh
#   ./cachyos-post-setup.sh              # actions + checks
#   ./cachyos-post-setup.sh --check-only # checks only, changes nothing

# NOTE: deliberately no `set -e`. A health check that dies on the first failed
# assertion can't report the other twelve.
set -uo pipefail

# ============================================================================
# FLAGS
# ============================================================================
CHECK_ONLY=false
SKIP_CLAUDE_CONFIG=false
for arg in "$@"; do
    case $arg in
        --check-only)          CHECK_ONLY=true ;;
        --no-claude-config)    SKIP_CLAUDE_CONFIG=true ;;
        -h|--help)
            echo "Usage: $0 [--check-only] [--no-claude-config]"
            echo "  --check-only         Run assertions only; make no changes."
            echo "  --no-claude-config   Skip re-running claude-config/install.sh."
            exit 0 ;;
    esac
done

# ============================================================================
# CONFIGURATION
# ============================================================================
WORK_DIR="$HOME/aerepo"
WORK_EMAIL="sprokopowich@angstromengineering.com"
WORK_SSH_ALIAS="github.com-work"
WORK_GH_USER="sprokopowich"
WORK_GH_ORG="AngstromEngineering"      # the discriminator — see check_gh_account
WORK_GH_CONFIG="$HOME/.config/gh-work"

PERSONAL_DIR="$HOME/repo"
PERSONAL_EMAIL="sprokopowich@proton.me"
PERSONAL_SSH_ALIAS="github.com-personal"
PERSONAL_GH_USER="sproko"
PERSONAL_GH_CONFIG="$HOME/.config/gh-personal"

# What gh falls back to anywhere outside the two project trees. Personal by
# design: everywhere except $WORK_DIR should answer as the personal account.
DEFAULT_GH_CONFIG="$HOME/.config/gh"

# Inbound SSH. Scoped to the home LAN rather than opened globally: these are
# laptops that end up on café and hotel wifi, where a plain `ufw allow 22` would
# expose the port to everyone else on that network. Deliberately a constant and
# not auto-detected — detecting at run time would happily open SSH to whatever
# network the machine is sitting on. Find the value with `ip -4 route show scope
# link`. Set to 0.0.0.0/0 to open it fully.
SSH_LAN_CIDR="192.168.1.0/24"

CLAUDE_CONFIG_DIR="$HOME/repo/claude-config"
# -C "$HOME" matters: without it, status prints paths relative to wherever the
# script was invoked from ("../../.config/…"), which is noise in a report.
DOTFILES_GIT=(git -C "$HOME" --git-dir="$HOME/.dotfiles" --work-tree="$HOME")

# Desktop apps not covered by the base setup — mostly AUR, so paru is required.
# teamviewer's Linux client is X11-only and cannot capture a Wayland session:
# outgoing sessions work, incoming ones get a black screen. rustdesk goes
# through the PipeWire portal, so it's the one that actually works for inbound
# control on Hyprland — both are here because they solve different directions.
#
# minizip is a repo package, listed because teamviewer's PKGBUILD doesn't
# declare it: without it teamviewerd dies at startup with exit 127 on a missing
# libminizip.so.1, and nothing in the install output hints at why. Must be
# minizip, not minizip-ng — the fork ships a different soname.
#
# nsis (Windows installer compiler) is AUR-only and builds from source against
# mingw-w64-gcc, so its first install is a long compile rather than a download.
# Budget for that on a fresh box; every other entry here is a fetch.
#
# powershell-bin, not powershell: same 7.6.x, but the plain AUR package builds
# .NET from source while -bin unpacks Microsoft's prebuilt tarball. It Provides
# powershell, so the check below has to query powershell-bin by its own name.
#
# gnome-keyring is the Secret Service provider: gitkraken links libsecret and
# has nowhere to put a token without it. Installing it is the whole setup —
# Arch's /etc/pam.d/sddm already carries the pam_gnome_keyring lines, prefixed
# with `-` so they no-op until the module exists. Takes effect on the next full
# SDDM login, not on this script's run. keepassxc is the personal vault and is
# deliberately NOT wired to the Secret Service: see the check below for why.
DESKTOP_APPS=(
    teams-for-linux-bin teamviewer rustdesk-bin minizip
    gnome-keyring seahorse keepassxc
    nsis powershell-bin
)

# ============================================================================
# OUTPUT HELPERS
# ============================================================================
if [ -t 1 ]; then
    C_OK=$'\033[32m'; C_BAD=$'\033[31m'; C_WARN=$'\033[33m'; C_OFF=$'\033[0m'
else
    C_OK=""; C_BAD=""; C_WARN=""; C_OFF=""
fi

PASS=0; FAIL=0; WARN=0
FAILURES=()

ok()   { printf '  %s✓%s %s\n' "$C_OK" "$C_OFF" "$1"; PASS=$((PASS + 1)); }
bad()  { printf '  %s✗%s %s\n' "$C_BAD" "$C_OFF" "$1"; FAIL=$((FAIL + 1)); FAILURES+=("$1"); }
warn() { printf '  %s!%s %s\n' "$C_WARN" "$C_OFF" "$1"; WARN=$((WARN + 1)); }

# Any ufw rule opening port 22. Reads the rules file rather than `ufw status`,
# which needs root — this keeps the check phase unprivileged. ufw records each
# rule as a "### tuple ###" line, written by backend_iptables.py as:
#   ### tuple ### <action> <protocol> <dport> <dst> <sport> <src> [...]
# so with the three "### tuple ###" tokens counted, dport is $6 and src is $9.
ufw_ssh_rule() {
    grep -h '^### tuple ###' /etc/ufw/user.rules /etc/ufw/user6.rules 2>/dev/null \
        | awk '$6 == "22"'
}

section() {
    echo ""
    echo "========================================================================"
    echo "$1"
    echo "========================================================================"
}

# Neither remote-access package enables its own daemon, and both fail quietly
# when it's missing: teamviewer's GUI just says "not ready", rustdesk simply
# never answers an inbound session. Keyed on is-active rather than is-enabled so
# an enabled-but-dead unit is recovered too — which is how teamviewerd lands
# when it first starts before minizip is installed.
ensure_service() {
    local pkg="$1" unit="$2"
    pacman -Q "$pkg" &>/dev/null || return 0
    systemctl is-active "$unit" &>/dev/null && return 0
    sudo systemctl enable --now "$unit" \
        && echo "  $unit enabled" \
        || echo "  WARNING: could not enable $unit"
}

echo "╔════════════════════════════════════════════════════════════════╗"
echo "║  CachyOS Post-Setup — finish and verify                       ║"
echo "╚════════════════════════════════════════════════════════════════╝"

# ============================================================================
# ACTIONS
# ============================================================================
if [ "$CHECK_ONLY" = false ]; then
    section "ACTIONS"

    # direnv drives the per-directory GH_CONFIG_DIR switch, and an .envrc stays
    # inert until it's been allowed once per machine.
    if command -v direnv &>/dev/null; then
        for d in "$WORK_DIR" "$PERSONAL_DIR"; do
            if [ -f "$d/.envrc" ]; then
                (cd "$d" && direnv allow) && echo "  direnv allow: $d"
            else
                echo "  no .envrc in $d — run dual-github-account-setup.sh first"
            fi
        done
    else
        echo "  direnv not installed — skipping (install it, then re-run)"
    fi

    # cachyos-auto-setup.sh enables sshd, but ufw defaults to DROP on input with
    # no rule for 22, so sshd ends up running and unreachable — nothing in either
    # script's output says so.
    if command -v ufw &>/dev/null && [ -n "$SSH_LAN_CIDR" ]; then
        if [ -n "$(ufw_ssh_rule)" ]; then
            echo "  ufw: a rule for :22 already exists — leaving it alone"
        else
            echo "  ufw: allowing SSH from $SSH_LAN_CIDR (sudo may prompt)..."
            if sudo ufw allow from "$SSH_LAN_CIDR" to any port 22 proto tcp; then
                echo "  ufw: SSH allowed from $SSH_LAN_CIDR"
            else
                echo "  WARNING: ufw rule failed — add by hand:"
                echo "           sudo ufw allow from $SSH_LAN_CIDR to any port 22 proto tcp"
            fi
        fi
    fi

    # install.sh regenerates CLAUDE.machine.md, which records the dotfiles branch.
    # Before the dotfiles checkout it says "~/.dotfiles not present", and nothing
    # refreshes it afterwards.
    if [ "$SKIP_CLAUDE_CONFIG" = false ] && [ -x "$CLAUDE_CONFIG_DIR/install.sh" ]; then
        echo "  running claude-config/install.sh (refreshes CLAUDE.machine.md)..."
        (cd "$CLAUDE_CONFIG_DIR" && ./install.sh) >/dev/null 2>&1 \
            && echo "  claude-config installed" \
            || echo "  WARNING: claude-config/install.sh failed — run it by hand"
    fi

    # Filter to what's actually missing first: --needed still makes paru fetch
    # and compare each AUR package, which is slow for a no-op re-run.
    if command -v paru &>/dev/null; then
        missing_apps=()
        for p in "${DESKTOP_APPS[@]}"; do
            pacman -Q "$p" &>/dev/null || missing_apps+=("$p")
        done
        if [ "${#missing_apps[@]}" -eq 0 ]; then
            echo "  desktop apps: all present"
        else
            echo "  installing from AUR: ${missing_apps[*]}"
            paru -S --needed --noconfirm "${missing_apps[@]}" \
                || echo "  WARNING: AUR install failed — run by hand: paru -S ${missing_apps[*]}"
        fi
    else
        echo "  paru not installed — skipping desktop apps"
    fi

    ensure_service teamviewer   teamviewerd
    ensure_service rustdesk-bin rustdesk
fi

# ============================================================================
# CHECKS: SSH — does each alias authenticate as the right GitHub user?
# ============================================================================
section "CHECKS: SSH key selection"

check_ssh_alias() {
    local host="$1" expect="$2" out
    # GitHub always exits non-zero here ("does not provide shell access"), so the
    # greeting text is the only usable signal — never the exit code.
    out=$(ssh -T -o BatchMode=yes -o ConnectTimeout=10 -o StrictHostKeyChecking=accept-new "$host" 2>&1)
    if grep -q "Hi ${expect}!" <<< "$out"; then
        ok "$host authenticates as $expect"
    elif grep -qi "permission denied\|could not resolve\|timed out" <<< "$out"; then
        bad "$host failed to authenticate: $(head -1 <<< "$out")"
    else
        # Authenticated, but as somebody else — the failure mode that shows up
        # later as a misleading "Repository not found" on a private repo.
        bad "$host authenticated as the WRONG account: $(head -1 <<< "$out")"
    fi
}

check_ssh_alias "$WORK_SSH_ALIAS" "$WORK_GH_USER"
check_ssh_alias "$PERSONAL_SSH_ALIAS" "$PERSONAL_GH_USER"

# ============================================================================
# CHECKS: git identity + URL rewrite, per directory
# ============================================================================
section "CHECKS: git identity by directory"

# includeIf "gitdir:" only matches inside an actual repository, so checking an
# empty tree just reports the global default and proves nothing. Probe with a
# throwaway repo instead.
check_identity() {
    local dir="$1" expect_email="$2" expect_host="$3"
    if [ ! -d "$dir" ]; then
        warn "$dir does not exist — skipping"
        return
    fi

    local probe="$dir/.post-setup-probe.$$"
    rm -rf "$probe"; mkdir -p "$probe"
    if ! git -C "$probe" init -q 2>/dev/null; then
        bad "could not create probe repo in $dir"
        rm -rf "$probe"; return
    fi

    local email rewritten
    email=$(git -C "$probe" config user.email 2>/dev/null)
    git -C "$probe" remote add origin "git@github.com:example/example.git" 2>/dev/null
    rewritten=$(git -C "$probe" ls-remote --get-url origin 2>/dev/null)
    rm -rf "$probe"

    [ "$email" = "$expect_email" ] \
        && ok "$dir → $email" \
        || bad "$dir → identity is '$email', expected '$expect_email'"

    [[ "$rewritten" == git@${expect_host}:* ]] \
        && ok "$dir → git@github.com: rewrites to $expect_host" \
        || bad "$dir → URL rewrite gave '$rewritten', expected git@$expect_host:…"
}

check_identity "$WORK_DIR" "$WORK_EMAIL" "$WORK_SSH_ALIAS"
check_identity "$PERSONAL_DIR" "$PERSONAL_EMAIL" "$PERSONAL_SSH_ALIAS"

# ============================================================================
# CHECKS: gh CLI account, per directory
# ============================================================================
section "CHECKS: gh account by directory"

# Separate auth path from SSH: gh uses its own OAuth token per GH_CONFIG_DIR, so
# a green SSH check says nothing about this one. Org membership is the reliable
# discriminator — the two accounts' logins are easy to transpose, and swapping
# the config dirs is exactly the mistake this catches.
check_gh_account() {
    local label="$1" cfg="$2" expect_login="$3" expect_org="${4:-}"

    if ! command -v gh &>/dev/null; then
        warn "gh not installed — skipping $label"
        return
    fi
    if [ ! -d "$cfg" ]; then
        bad "$label: $cfg missing — run 'gh auth login' from that directory"
        return
    fi

    local login
    login=$(GH_CONFIG_DIR="$cfg" gh api user --jq '.login' 2>/dev/null)
    if [ -z "$login" ]; then
        warn "$label: not logged in (or offline) — 'gh auth login' in that directory"
        return
    fi

    [ "$login" = "$expect_login" ] \
        && ok "$label → $login" \
        || bad "$label → logged in as '$login', expected '$expect_login' (config dirs swapped?)"

    local orgs
    orgs=$(GH_CONFIG_DIR="$cfg" gh api user/orgs --jq '[.[].login] | join(",")' 2>/dev/null)
    if [ -n "$expect_org" ]; then
        grep -q "$expect_org" <<< "$orgs" \
            && ok "$label → can see $expect_org" \
            || bad "$label → cannot see $expect_org (orgs: ${orgs:-none})"
    fi
}

check_gh_account "$WORK_DIR"     "$WORK_GH_CONFIG"     "$WORK_GH_USER" "$WORK_GH_ORG"
check_gh_account "$PERSONAL_DIR" "$PERSONAL_GH_CONFIG" "$PERSONAL_GH_USER"
check_gh_account "default"       "$DEFAULT_GH_CONFIG"  "$PERSONAL_GH_USER"

# check_gh_account only asks who the ACTIVE account is, which still passes when
# both logins landed in one config — the state `gh auth login` leaves behind
# when it runs somewhere direnv hasn't exported GH_CONFIG_DIR (a non-fish shell,
# or an editor's shell-out). gh then answers as whichever account is active,
# everywhere, and nothing says so. Assert the default holds one account only.
if command -v gh &>/dev/null && [ -d "$DEFAULT_GH_CONFIG" ]; then
    n_default=$(GH_CONFIG_DIR="$DEFAULT_GH_CONFIG" gh auth status 2>/dev/null | grep -c 'Logged in to')
    [ "$n_default" -le 1 ] \
        && ok "default gh config holds a single account" \
        || bad "default gh config holds $n_default accounts — prune with: GH_CONFIG_DIR=$DEFAULT_GH_CONFIG gh auth logout --user $WORK_GH_USER"
fi

# ============================================================================
# CHECKS: desktop config health
# ============================================================================
section "CHECKS: desktop config"

if command -v hyprctl &>/dev/null && hyprctl monitors &>/dev/null; then
    errs=$(hyprctl configerrors 2>/dev/null | grep -v '^$')
    [ -z "$errs" ] && ok "hyprland config has no errors" || bad "hyprland config errors: $errs"

    # Per-host overrides only apply if this host actually has a file.
    host_lua="$HOME/.config/hypr/config/host/$(uname -n).lua"
    [ -f "$host_lua" ] \
        && ok "per-host hypr override present: $(basename "$host_lua")" \
        || warn "no per-host hypr override for $(uname -n) (fine if the shared config suits it)"
else
    warn "hyprland not running — skipping hypr checks"
fi

# A version bump silently renames settings; validate is the only thing that says so.
if command -v noctalia &>/dev/null; then
    nout=$(noctalia config validate 2>&1)
    if grep -q "warning" <<< "$nout"; then
        bad "noctalia config has warnings: $(grep -c WARN <<< "$nout") (run: noctalia config validate)"
    elif grep -q "valid" <<< "$nout"; then
        ok "noctalia config valid, no warnings"
    else
        warn "noctalia config validate said: $(head -1 <<< "$nout")"
    fi
fi

# ============================================================================
# CHECKS: remote access
# ============================================================================
section "CHECKS: remote access (sshd + firewall)"

sshd_up=false
if [ "$(systemctl is-active sshd 2>/dev/null)" = "active" ]; then
    sshd_up=true
    ok "sshd running ($(systemctl is-enabled sshd 2>/dev/null) at boot)"
else
    bad "sshd not running — systemctl enable --now sshd"
fi

if command -v ufw &>/dev/null && [ "$(systemctl is-active ufw 2>/dev/null)" = "active" ]; then
    rule=$(ufw_ssh_rule)
    if [ -n "$rule" ]; then
        # Report the source, so an unexpectedly wide rule is visible rather than
        # just showing a green tick.
        rule_src=$(awk '{print $9}' <<< "$rule" | paste -sd, -)
        ok "ufw allows :22 from $rule_src"

        # A LAN-scoped rule is correctly unreachable from anywhere else, which
        # otherwise looks like a broken firewall when you're travelling.
        if [ "$rule_src" != "0.0.0.0/0" ] \
           && ! ip -4 route show scope link 2>/dev/null | grep -qF "$rule_src"; then
            warn "not currently on $rule_src — SSH to this box is expected to be unreachable from here"
        fi
    elif [ "$(grep -c '^DEFAULT_INPUT_POLICY="DROP"' /etc/default/ufw 2>/dev/null)" -gt 0 ]; then
        # The trap this check exists for: sshd listening, ufw dropping, no error anywhere.
        bad "ufw is active with a DROP input policy and no rule for :22 — inbound SSH is blocked"
    else
        warn "ufw active, no explicit :22 rule (input policy is not DROP, so it may still be reachable)"
    fi
elif [ "$sshd_up" = true ]; then
    warn "ufw not active — :22 governed by whatever else is filtering, if anything"
fi

# ============================================================================
# CHECKS: dotfiles hygiene
# ============================================================================
section "CHECKS: dotfiles"

if [ -d "$HOME/.dotfiles" ]; then
    branch=$("${DOTFILES_GIT[@]}" branch --show-current 2>/dev/null)
    ok "dotfiles on branch: $branch"

    # Drift right after setup usually means a tool owns a tracked file and keeps
    # regenerating it (noctalia rewrites the theme includes it templates).
    drift=$("${DOTFILES_GIT[@]}" status --short 2>/dev/null)
    [ -z "$drift" ] \
        && ok "no uncommitted dotfiles drift" \
        || warn "dotfiles drift: $(wc -l <<< "$drift") file(s) — $(tr '\n' ' ' <<< "$drift")"

    if [ -n "$(${DOTFILES_GIT[@]} log --oneline "@{u}.." 2>/dev/null)" ]; then
        warn "dotfiles has unpushed commits"
    fi
else
    warn "~/.dotfiles not present — run cachyos-auto-setup.sh --full"
fi

# ============================================================================
# CHECKS: dev environment
# ============================================================================
section "CHECKS: dev environment"

groups | tr ' ' '\n' | grep -qx docker \
    && ok "docker group active in this session" \
    || bad "docker group not active — log out and back in"

if command -v dotnet &>/dev/null; then
    ok "dotnet present ($(dotnet --version 2>/dev/null))"
    # The path is set in the login shell's config, so check the real thing rather
    # than this script's inherited PATH.
    if [ -d "$HOME/.dotnet/tools" ]; then
        if fish -c 'contains $HOME/.dotnet/tools $PATH' 2>/dev/null; then
            ok "~/.dotnet/tools on PATH in fish"
        else
            bad "~/.dotnet/tools exists but is NOT on fish's PATH (hardcoded home in config.fish?)"
        fi
    fi
fi

command -v direnv &>/dev/null \
    && ok "direnv installed" \
    || bad "direnv missing — per-directory gh switching won't work"

# ============================================================================
# CHECKS: desktop apps
# ============================================================================
section "CHECKS: apps"

for p in "${DESKTOP_APPS[@]}"; do
    pacman -Q "$p" &>/dev/null \
        && ok "$p installed" \
        || bad "$p missing — paru -S $p"
done

if pacman -Q teamviewer &>/dev/null; then
    systemctl is-active teamviewerd &>/dev/null \
        && ok "teamviewerd running" \
        || bad "teamviewerd not running — sudo systemctl enable --now teamviewerd"
    # Stated up front rather than discovered halfway through a support call.
    [ "${XDG_SESSION_TYPE:-}" = wayland ] \
        && warn "teamviewer can't capture a Wayland session — inbound control needs rustdesk"
fi

if pacman -Q rustdesk-bin &>/dev/null; then
    # Without the service, rustdesk only answers while its GUI window is open.
    systemctl is-active rustdesk &>/dev/null \
        && ok "rustdesk service running" \
        || bad "rustdesk service not running — sudo systemctl enable --now rustdesk"
fi

if pacman -Q gnome-keyring &>/dev/null; then
    # gnome-keyring and kwallet's secretservicecompat both want to own
    # org.freedesktop.secrets, and whichever claims it first keeps it. If
    # kwallet wins, gitkraken's token goes into a wallet nothing else reads and
    # no error is raised anywhere. GetConnectionUnixProcessID doesn't D-Bus
    # activate, so asking cannot itself decide the race.
    secrets_pid=$(busctl --user call org.freedesktop.DBus /org/freedesktop/DBus \
        org.freedesktop.DBus GetConnectionUnixProcessID s org.freedesktop.secrets 2>/dev/null \
        | awk '/^u /{print $2}')
    if [ -z "$secrets_pid" ]; then
        warn "no Secret Service running yet — full SDDM re-login starts it via pam_gnome_keyring"
    else
        secrets_comm=$(cat "/proc/$secrets_pid/comm" 2>/dev/null)
        case "$secrets_comm" in
            gnome-keyring*) ok "Secret Service owned by $secrets_comm" ;;
            *) bad "Secret Service owned by '${secrets_comm:-unknown}', expected gnome-keyring — app tokens will land somewhere nothing else reads" ;;
        esac
    fi
fi

# ============================================================================
# SUMMARY
# ============================================================================
section "SUMMARY"
printf '  %s%d passed%s   %s%d failed%s   %s%d warnings%s\n' \
    "$C_OK" "$PASS" "$C_OFF" "$C_BAD" "$FAIL" "$C_OFF" "$C_WARN" "$WARN" "$C_OFF"

if [ "$FAIL" -gt 0 ]; then
    echo ""
    echo "  Failures:"
    for f in "${FAILURES[@]}"; do echo "    - $f"; done
    echo ""
    exit 1
fi

echo ""
echo "  All good."
exit 0
