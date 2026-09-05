#!/bin/bash
# Dual GitHub Account Setup - Work + Personal, keyed by directory
# Run this BEFORE cachyos-auto-setup.sh on a fresh machine. It sets up:
#   - Two SSH keypairs (work / personal), aliased in ~/.ssh/config
#   - ~/.gitconfig with includeIf blocks so commit identity + SSH key follow
#     which directory you're in (~/aerepo = work, ~/repo = personal)
#   - direnv hook in fish + a .envrc per directory pointing gh at a separate
#     GH_CONFIG_DIR, so `gh` also auto-switches accounts by directory
#
# cachyos-auto-setup.sh has a guard that detects this setup (via the
# includeIf in ~/.gitconfig) and preserves all the files this script writes
# across its dotfiles checkout — safe to run this first, then that script.
#
# Idempotent: safe to re-run. Existing keys/files are left alone, not
# overwritten; only missing pieces are added.
#
# Make executable before running:
#   chmod +x dual-github-account-setup.sh
#   ./dual-github-account-setup.sh

set -e  # Exit on error

# ============================================================================
# CONFIGURATION - Modify these to customize your setup
# ============================================================================
GIT_USER_NAME="Steve Prokopowich"

WORK_DIR="$HOME/aerepo"
WORK_EMAIL="sprokopowich@angstromengineering.com"
WORK_KEY="$HOME/.ssh/id_ed25519_work"
WORK_SSH_ALIAS="github.com-work"

PERSONAL_DIR="$HOME/repo"
PERSONAL_EMAIL="sprokopowich@proton.me"
PERSONAL_KEY="$HOME/.ssh/id_ed25519_personal"
PERSONAL_SSH_ALIAS="github.com-personal"

echo "╔════════════════════════════════════════════════════════════════╗"
echo "║  Dual GitHub Account Setup (work + personal, by directory)    ║"
echo "╚════════════════════════════════════════════════════════════════╝"
echo ""

# ============================================================================
# STEP 1/6: Repo directories
# ============================================================================
echo "========================================================================"
echo "STEP 1/6: Creating repo directories"
echo "========================================================================"
mkdir -p "$WORK_DIR" "$PERSONAL_DIR"
echo "  $WORK_DIR"
echo "  $PERSONAL_DIR"

# ============================================================================
# STEP 2/6: SSH keys
# ============================================================================
echo ""
echo "========================================================================"
echo "STEP 2/6: Generating SSH keys (skipped if they already exist)"
echo "========================================================================"
mkdir -p "$HOME/.ssh" && chmod 700 "$HOME/.ssh"

if [ -f "$WORK_KEY" ]; then
    echo "  $WORK_KEY already exists, skipping."
else
    ssh-keygen -t ed25519 -C "$WORK_EMAIL" -f "$WORK_KEY" -N "" -q
    chmod 600 "$WORK_KEY" && chmod 644 "$WORK_KEY.pub"
    echo "  generated $WORK_KEY"
fi

if [ -f "$PERSONAL_KEY" ]; then
    echo "  $PERSONAL_KEY already exists, skipping."
else
    ssh-keygen -t ed25519 -C "$PERSONAL_EMAIL" -f "$PERSONAL_KEY" -N "" -q
    chmod 600 "$PERSONAL_KEY" && chmod 644 "$PERSONAL_KEY.pub"
    echo "  generated $PERSONAL_KEY"
fi

# ============================================================================
# STEP 3/6: ~/.ssh/config Host aliases
# ============================================================================
echo ""
echo "========================================================================"
echo "STEP 3/6: Writing ~/.ssh/config Host aliases"
echo "========================================================================"
SSH_CONFIG="$HOME/.ssh/config"
touch "$SSH_CONFIG" && chmod 600 "$SSH_CONFIG"

add_ssh_host_block() {
    local alias="$1" key="$2"
    if grep -q "^Host $alias\$" "$SSH_CONFIG" 2>/dev/null; then
        echo "  Host $alias already present in $SSH_CONFIG, skipping."
    else
        {
            echo "Host $alias"
            echo "    HostName github.com"
            echo "    User git"
            echo "    IdentityFile $key"
            echo "    IdentitiesOnly yes"
            echo ""
        } >> "$SSH_CONFIG"
        echo "  added Host $alias"
    fi
}
add_ssh_host_block "$WORK_SSH_ALIAS" "$WORK_KEY"
add_ssh_host_block "$PERSONAL_SSH_ALIAS" "$PERSONAL_KEY"

# ============================================================================
# STEP 4/6: Git identity — ~/.gitconfig includeIf + per-account files
# ============================================================================
echo ""
echo "========================================================================"
echo "STEP 4/6: Configuring git identity (includeIf by directory)"
echo "========================================================================"
GITCONFIG="$HOME/.gitconfig"

if [ -f "$GITCONFIG" ] && grep -q 'includeIf' "$GITCONFIG" 2>/dev/null; then
    echo "  $GITCONFIG already has includeIf blocks, leaving it as-is."
else
    if [ -f "$GITCONFIG" ]; then
        cp -a "$GITCONFIG" "$GITCONFIG.bak.$(date +%Y%m%d%H%M%S)"
        echo "  GUARD: backed up existing $GITCONFIG before rewriting."
    fi
    cat > "$GITCONFIG" << EOF
[user]
    name = $GIT_USER_NAME
    email = $PERSONAL_EMAIL

[includeIf "gitdir:$WORK_DIR/"]
    path = ~/.gitconfig-work

[includeIf "gitdir:$PERSONAL_DIR/"]
    path = ~/.gitconfig-personal
EOF
    echo "  wrote $GITCONFIG"
fi

write_account_gitconfig() {
    local file="$1" email="$2" alias="$3"
    if [ -f "$file" ]; then
        echo "  $file already exists, leaving it as-is."
    else
        cat > "$file" << EOF
[user]
    email = $email

[url "git@$alias:"]
    insteadOf = git@github.com:
EOF
        echo "  wrote $file"
    fi
}
write_account_gitconfig "$HOME/.gitconfig-work" "$WORK_EMAIL" "$WORK_SSH_ALIAS"
write_account_gitconfig "$HOME/.gitconfig-personal" "$PERSONAL_EMAIL" "$PERSONAL_SSH_ALIAS"

# ============================================================================
# STEP 5/6: direnv — fish hook + per-directory GH_CONFIG_DIR
# ============================================================================
echo ""
echo "========================================================================"
echo "STEP 5/6: Configuring direnv (fish hook + .envrc per directory)"
echo "========================================================================"
FISH_CONFIG="$HOME/.config/fish/config.fish"
mkdir -p "$(dirname "$FISH_CONFIG")"
touch "$FISH_CONFIG"

if grep -q 'direnv hook fish' "$FISH_CONFIG" 2>/dev/null; then
    echo "  direnv hook already present in $FISH_CONFIG, skipping."
else
    {
        echo ""
        echo "if type -q direnv"
        echo "    direnv hook fish | source"
        echo "end"
    } >> "$FISH_CONFIG"
    echo "  added direnv hook to $FISH_CONFIG"
fi

write_envrc() {
    local dir="$1" config_dir="$2"
    local envrc="$dir/.envrc"
    if [ -f "$envrc" ]; then
        echo "  $envrc already exists, leaving it as-is."
    else
        echo "export GH_CONFIG_DIR=\"$config_dir\"" > "$envrc"
        echo "  wrote $envrc"
    fi
}
write_envrc "$WORK_DIR" "$HOME/.config/gh-work"
write_envrc "$PERSONAL_DIR" "$HOME/.config/gh-personal"

# ============================================================================
# STEP 6/6: Summary + manual next steps
# ============================================================================
echo ""
echo "========================================================================"
echo "STEP 6/6: Summary"
echo "========================================================================"
echo ""
echo "╔════════════════════════════════════════════════════════════════╗"
echo "║                          SETUP COMPLETE                        ║"
echo "╚════════════════════════════════════════════════════════════════╝"
echo ""
echo "WORK public key ($WORK_EMAIL) — add at github.com/settings/keys"
echo "on the WORK account:"
echo ""
cat "$WORK_KEY.pub"
echo ""
echo "PERSONAL public key ($PERSONAL_EMAIL) — add at github.com/settings/keys"
echo "on the PERSONAL account:"
echo ""
cat "$PERSONAL_KEY.pub"
echo ""
echo "Manual steps still required:"
echo "  1. sudo pacman -S github-cli direnv     (if not already installed)"
echo "  2. Add each public key above to its matching GitHub account"
echo "  3. Restart your shell (or 'exec fish'), then:"
echo "       cd $WORK_DIR && direnv allow"
echo "       cd $PERSONAL_DIR && direnv allow"
echo "  4. Log in to gh separately, from inside each directory:"
echo "       cd $WORK_DIR && gh auth login       (choose SSH, log in as work account)"
echo "       cd $PERSONAL_DIR && gh auth login   (choose SSH, log in as personal account)"
echo ""
echo "After that, cachyos-auto-setup.sh is safe to run — it detects this"
echo "setup via the includeIf in ~/.gitconfig and preserves it across the"
echo "dotfiles checkout."
