#!/bin/bash
# CachyOS Unattended Setup Script - Complete Hyprland Development Environment
# Mirrors the structure of debian-auto-setup.sh, adapted for CachyOS (Arch-based)
# Run as regular user (will prompt for sudo password once at start)
#
# Make executable before running:
#   chmod +x cachyos-auto-setup.sh
#   ./cachyos-auto-setup.sh

set -e  # Exit on error

# ============================================================================
# FLAGS
# ============================================================================
MODE=""
DOTFILES_BRANCH_ARG=""
GIT_NAME_ARG=""
GIT_EMAIL_ARG=""
for arg in "$@"; do
    case $arg in
        --full)                MODE="full" ;;
        --dev-only)            MODE="dev" ;;
        --dotfiles-branch=*)   DOTFILES_BRANCH_ARG="${arg#*=}" ;;
        --git-name=*)          GIT_NAME_ARG="${arg#*=}" ;;
        --git-email=*)         GIT_EMAIL_ARG="${arg#*=}" ;;
    esac
done

if [ -z "$MODE" ]; then
    echo "Usage: $0 <mode> [--dotfiles-branch=NAME] [--git-name=NAME] [--git-email=EMAIL]"
    echo ""
    echo "  --full                  Full setup: Hyprland, SDDM, dotfiles, dev tools, fonts, zsh, etc."
    echo "  --dev-only              Dev tools only: .NET, Docker, EF Core, optional CLI tools"
    echo ""
    echo "  --dotfiles-branch=NAME  (full mode) Use this dotfiles branch without prompting."
    echo "                          Omit to be shown a menu of available branches."
    echo ""
    echo "  --git-name=NAME         Bootstrap git user.name without prompting."
    echo "  --git-email=EMAIL       Bootstrap git user.email without prompting."
    echo "                          Both are skipped entirely if a two-account"
    echo "                          ~/.gitconfig (from dual-github-account-setup.sh)"
    echo "                          is already in place. Omit either to be prompted."
    echo ""
    exit 1
fi

# ============================================================================
# CONFIGURATION - Modify these to customize your installation
# ============================================================================

# Git configuration — used only to bootstrap ~/.gitconfig before the dotfiles
# checkout, and only on a machine that doesn't already have a two-account
# setup (see PRESERVE_GITCONFIG below). Leave blank to be prompted at STEP 13;
# --git-name=/--git-email= override without prompting.
GIT_USER_NAME=""
GIT_USER_EMAIL=""
[ -n "$GIT_NAME_ARG" ] && GIT_USER_NAME="$GIT_NAME_ARG"
[ -n "$GIT_EMAIL_ARG" ] && GIT_USER_EMAIL="$GIT_EMAIL_ARG"

# Bluetooth device to auto-connect (set to empty string to skip)
BLUETOOTH_DEVICE_MAC="db:b6:a2:f7:f6:e8"

# Dotfiles bare repo
DOTFILES_REPO="git@github.com:sproko/dotfiles-v2.git"
# Which dotfiles branch to check out. Different machines use different branches
# (e.g. hyprland-arch = .conf/waybar setup, noctalia-cachyos = Noctalia/Lua).
# Leave empty to be prompted with a menu; --dotfiles-branch=NAME overrides.
DOTFILES_BRANCH=""
[ -n "$DOTFILES_BRANCH_ARG" ] && DOTFILES_BRANCH="$DOTFILES_BRANCH_ARG"
# SSH key to use for the dotfiles clone (a sproko/personal repo). If this file
# exists it's forced for the clone, so it works even on a machine whose default
# github.com key is a different account. Empty = use whatever ssh picks.
DOTFILES_SSH_KEY="$HOME/.ssh/id_ed25519_personal"

# Wallpaper source — resolved relative to this script so the repo ships the image
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
WALLPAPER_SOURCE="$SCRIPT_DIR/../Backgrounds/Arch-png-wallpapers.jpg"

# Installation options
INSTALL_DOTNET_SDK=true           # Install .NET SDK via AUR (dotnet-sdk-bin)
INSTALL_DOTNET_VERSION="10.0"     # .NET version (8.0, 9.0, or 10.0)
INSTALL_DOCKER=true               # Install Docker Engine
INSTALL_EF_TOOLS=true             # Install Entity Framework CLI tools
INSTALL_OMZ=true                  # Install Oh-My-Zsh
INSTALL_STARSHIP=true             # Install Starship prompt (works with Oh-My-Zsh)
INSTALL_NERD_FONTS=true           # Install Nerd Fonts via AUR
INSTALL_BLUETOOTH=true            # Install Bluetooth stack
INSTALL_OPTIONAL_TOOLS=true       # Install fzf, ripgrep, bat, eza, lazygit, etc.
INSTALL_HYPRLAND_EXTRAS=true      # Install sddm-astronaut-theme, wlopm, etc.

# ============================================================================
# SCRIPT START - Do not modify below unless you know what you're doing
# ============================================================================

if [ "$MODE" = "full" ]; then
echo "╔════════════════════════════════════════════════════════════════╗"
echo "║  CachyOS Unattended Setup - Hyprland Development Environment  ║"
echo "║  This will take 10-20 minutes depending on your connection    ║"
echo "╚════════════════════════════════════════════════════════════════╝"
else
echo "╔════════════════════════════════════════════════════════════════╗"
echo "║  CachyOS Dev Environment Setup                                ║"
echo "║  Installing: .NET, Docker, EF Core, optional CLI tools        ║"
echo "╚════════════════════════════════════════════════════════════════╝"
fi
echo ""

# ============================================================================
# SAFETY GUARDS - Detect an already-configured machine so we don't clobber it
# ============================================================================
# If this box already has the two-account git/ssh/direnv setup (from
# dual-github-account-setup.sh) or a customized login shell, we preserve them
# instead of overwriting with the dotfiles/zsh defaults. The dotfiles checkout
# in STEP 13 only touches paths the dotfiles repo tracks, but several of these
# files (ssh config, fish config) are exactly the kind of thing a dotfiles repo
# tracks — so anything in this list gets backed up before checkout and
# restored after, regardless of whether this particular dotfiles branch
# happens to track it.
PRESERVE_GITCONFIG=false
DUAL_ACCOUNT_FILES=(
    "$HOME/.gitconfig"
    "$HOME/.gitconfig-personal"
    "$HOME/.gitconfig-work"
    "$HOME/.ssh/config"
    "$HOME/.config/fish/config.fish"
    "$HOME/aerepo/.envrc"
    "$HOME/repo/.envrc"
)
if [ -f "$HOME/.gitconfig" ] && grep -q 'includeIf' "$HOME/.gitconfig" 2>/dev/null; then
    PRESERVE_GITCONFIG=true
    DUAL_ACCOUNT_PRESERVE_DIR="$(mktemp -d)"
    echo "GUARD: existing two-account git/ssh/fish setup detected — preserving these across the dotfiles checkout:"
    for f in "${DUAL_ACCOUNT_FILES[@]}"; do
        if [ -f "$f" ]; then
            echo "  - $f"
            mkdir -p "$DUAL_ACCOUNT_PRESERVE_DIR/$(dirname "$f")"
            cp -a "$f" "$DUAL_ACCOUNT_PRESERVE_DIR/$f"
        fi
    done
fi

# Login shell from passwd (not $SHELL, which is whatever ran this script).
CURRENT_LOGIN_SHELL="$(getent passwd "$USER" | cut -d: -f7)"

# Get sudo access upfront
echo "Please enter your sudo password to begin installation..."
sudo -v

# Keep sudo alive throughout the script
while true; do sudo -n true; sleep 60; kill -0 "$$" || exit; done 2>/dev/null &

# ============================================================================
# STEP 1/16: System Update
# ============================================================================
echo ""
echo "========================================================================"
echo "STEP 1/16: Updating System Packages"
echo "========================================================================"
sudo pacman -Syu --noconfirm

# ============================================================================
# STEP 2/16: Install paru (AUR helper)
# ============================================================================
echo ""
echo "========================================================================"
echo "STEP 2/16: Installing paru (AUR Helper)"
echo "========================================================================"
if command -v paru &>/dev/null; then
    echo "paru is already installed, skipping."
else
    echo "paru not found — cloning and building from AUR..."
    sudo pacman -S --noconfirm --needed git base-devel
    PARU_TMP=$(mktemp -d)
    git clone https://aur.archlinux.org/paru.git "$PARU_TMP/paru"
    pushd "$PARU_TMP/paru" > /dev/null
    makepkg -si --noconfirm
    popd > /dev/null
    rm -rf "$PARU_TMP"
    echo "paru installed successfully"
fi

if [ "$MODE" = "full" ]; then
# ============================================================================
# STEP 3/16: Install Hyprland Stack
# ============================================================================
echo ""
echo "========================================================================"
echo "STEP 3/16: Installing Hyprland Stack (Wayland compositor + tools)"
echo "========================================================================"
sudo pacman -S --noconfirm --needed \
    hyprland \
    hyprlock \
    hypridle \
    hyprpaper \
    waybar \
    wofi \
    alacritty \
    swaync \
    swww \
    wlogout \
    cliphist \
    grim \
    slurp \
    polkit-kde-agent \
    qt5-wayland \
    qt6-wayland \
    xdg-desktop-portal-hyprland \
    xdg-user-dirs

if [ "$INSTALL_HYPRLAND_EXTRAS" = true ]; then
    echo "Installing Hyprland extras (wlopm) from AUR..."
    paru -S --noconfirm --needed wlopm || true
fi
fi # end --full only

# ============================================================================
# STEP 4/16: Install Basic Dev Tools
# ============================================================================
echo ""
echo "========================================================================"
echo "STEP 4/16: Installing Basic Development Tools"
echo "========================================================================"
sudo pacman -S --noconfirm --needed \
    git \
    git-lfs \
    base-devel \
    cmake \
    neovim \
    tmux \
    htop \
    tree \
    curl \
    wget \
    unzip \
    direnv \
    openssh

if [ "$INSTALL_OPTIONAL_TOOLS" = true ]; then
    echo "Installing optional modern CLI tools (fzf, ripgrep, bat, eza, lazygit, fd)..."
    sudo pacman -S --noconfirm --needed \
        fzf \
        ripgrep \
        fd \
        bat \
        eza \
        lazygit
fi

# ============================================================================
# STEP 5/16: Install .NET SDK
# ============================================================================
echo ""
echo "========================================================================"
echo "STEP 5/16: Installing .NET SDK"
echo "========================================================================"
if [ "$INSTALL_DOTNET_SDK" = true ]; then
    # Versioned AUR packages (dotnet-sdk-8.0-bin, dotnet-sdk-9.0-bin) exist for LTS only.
    # For the current release (10+), dotnet-sdk-bin is the right package.
    case "$INSTALL_DOTNET_VERSION" in
        8.0|9.0) DOTNET_PKG="dotnet-sdk-${INSTALL_DOTNET_VERSION}-bin" ;;
        *)       DOTNET_PKG="dotnet-sdk-bin" ;;
    esac
    echo "Installing $DOTNET_PKG from AUR..."
    paru -S --noconfirm --needed "$DOTNET_PKG"
    echo ".NET SDK installed:"
    dotnet --version
else
    echo "Skipping .NET SDK installation (disabled in config)"
fi

# ============================================================================
# STEP 6/16: Install Docker
# ============================================================================
echo ""
echo "========================================================================"
echo "STEP 6/16: Installing Docker Engine"
echo "========================================================================"
if [ "$INSTALL_DOCKER" = true ]; then
    sudo pacman -S --noconfirm --needed docker docker-compose
    sudo systemctl start docker
    sudo systemctl enable docker
    sudo usermod -aG docker "$USER"
    echo "Docker installed. NOTE: Log out and back in for docker group to take effect"
else
    echo "Skipping Docker installation (disabled in config)"
fi

if [ "$MODE" = "full" ]; then
# ============================================================================
# STEP 7/16: Install Audio Stack (PipeWire)
# ============================================================================
echo ""
echo "========================================================================"
echo "STEP 7/16: Installing Audio Stack (PipeWire)"
echo "========================================================================"
# Remove real jack/jack2 only if actually (literally) installed. Two gotchas
# here: passing a target pacman doesn't recognize aborts the whole -R with no
# removal at all (the old `2>/dev/null || true` hid that, leaving jack2 in
# place to conflict with pipewire-jack below); and `pacman -Q jack` alone
# isn't a safe existence check either — jack2 declares `provides=jack`, so
# `pacman -Q jack` reports success (resolving via provides) even though no
# package is literally named "jack", and `pacman -R jack` then fails with
# "target not found". Check literal installed package names instead.
INSTALLED_PKGS="$(pacman -Qq)"
for JACK_PKG in jack jack2; do
    if grep -qx "$JACK_PKG" <<< "$INSTALLED_PKGS"; then
        sudo pacman -Rdd --noconfirm "$JACK_PKG"
    fi
done
sudo pacman -S --noconfirm --needed \
    pipewire \
    pipewire-pulse \
    pipewire-alsa \
    pipewire-jack \
    wireplumber \
    pavucontrol

systemctl --user enable --now wireplumber.service 2>/dev/null || true
systemctl --user enable --now pipewire.service 2>/dev/null || true
systemctl --user enable --now pipewire-pulse.service 2>/dev/null || true
echo "PipeWire audio stack installed"

# ============================================================================
# STEP 8/16: Install Bluetooth Stack
# ============================================================================
echo ""
echo "========================================================================"
echo "STEP 8/16: Installing Bluetooth Stack"
echo "========================================================================"
if [ "$INSTALL_BLUETOOTH" = true ]; then
    sudo pacman -S --noconfirm --needed \
        bluez \
        bluez-utils \
        blueman

    sudo systemctl start bluetooth
    sudo systemctl enable bluetooth
    echo "Bluetooth stack installed"
else
    echo "Skipping Bluetooth installation (disabled in config)"
fi

# ============================================================================
# STEP 9/16: Ensure NetworkManager is Active
# ============================================================================
echo ""
echo "========================================================================"
echo "STEP 9/16: Configuring NetworkManager"
echo "========================================================================"
if ! pacman -Q networkmanager &>/dev/null; then
    echo "NetworkManager not found — installing..."
    sudo pacman -S --noconfirm --needed networkmanager
fi
sudo systemctl enable --now NetworkManager
echo "NetworkManager is active"

# ============================================================================
# STEP 10/16: Install Nerd Fonts
# ============================================================================
echo ""
echo "========================================================================"
echo "STEP 10/16: Installing Nerd Fonts (via AUR)"
echo "========================================================================"
if [ "$INSTALL_NERD_FONTS" = true ]; then
    paru -S --noconfirm --needed \
        ttf-jetbrains-mono-nerd \
        ttf-ubuntu-nerd \
        ttf-firacode-nerd

    fc-cache -fv
    echo "Nerd Fonts installed:"
    fc-list | grep -i "Nerd Font" | cut -d: -f2 | sort -u | head -n 6
else
    echo "Skipping Nerd Fonts installation (disabled in config)"
fi

# ============================================================================
# STEP 11/16: Install zsh + Oh-My-Zsh + Starship
# ============================================================================
echo ""
echo "========================================================================"
echo "STEP 11/16: Installing zsh, Oh-My-Zsh, and Starship"
echo "========================================================================"
if [ "$INSTALL_OMZ" = true ]; then
    sudo pacman -S --noconfirm --needed zsh

    echo "Installing Oh-My-Zsh..."
    export RUNZSH=no
    export KEEP_ZSHRC=yes
    sh -c "$(curl -fsSL https://raw.githubusercontent.com/ohmyzsh/ohmyzsh/master/tools/install.sh)" "" --unattended
    echo "Oh-My-Zsh installed"
else
    echo "Skipping Oh-My-Zsh installation (disabled in config)"
fi

if [ "$INSTALL_STARSHIP" = true ]; then
    echo "Installing Starship prompt..."
    curl -sS https://starship.rs/install.sh | sh -s -- -y
    echo "Starship installed"
else
    echo "Skipping Starship installation (disabled in config)"
fi

# ============================================================================
# STEP 12/16: Install SDDM + sddm-astronaut-theme (Catppuccin Mocha)
# ============================================================================
echo ""
echo "========================================================================"
echo "STEP 12/16: Installing SDDM Display Manager + Catppuccin Mocha theme"
echo "========================================================================"
sudo pacman -S --noconfirm --needed sddm

if [ "$INSTALL_HYPRLAND_EXTRAS" = true ]; then
    echo "Installing sddm-astronaut-theme from AUR..."
    paru -S --noconfirm --needed sddm-astronaut-theme || true

    THEME_DIR="/usr/share/sddm/themes/sddm-astronaut-theme"

    if [ -d "$THEME_DIR" ]; then
        # Copy wallpaper into theme Backgrounds folder and ~/Pictures for hyprpaper
        if [ -f "$WALLPAPER_SOURCE" ]; then
            sudo cp "$WALLPAPER_SOURCE" "$THEME_DIR/Backgrounds/arch_wallpaper.jpg"
            mkdir -p "$HOME/Pictures"
            cp "$WALLPAPER_SOURCE" "$HOME/Pictures/arch_wallpaper.jpg"
            echo "Wallpaper copied to theme Backgrounds/ and ~/Pictures/"
        else
            echo "WARNING: Wallpaper not found at $WALLPAPER_SOURCE"
            echo "         You will need to manually copy a wallpaper to:"
            echo "         $THEME_DIR/Backgrounds/arch_wallpaper.jpg"
            echo "         $HOME/Pictures/arch_wallpaper.jpg"
        fi

        # Write Catppuccin Mocha theme config
        echo "Writing catppuccin_mocha.conf..."
        sudo tee "$THEME_DIR/Themes/catppuccin_mocha.conf" > /dev/null << 'SDDMTHEME'
[General]
ScreenWidth="2560"
ScreenHeight="1440"
ScreenPadding=""

Font="JetBrainsMono Nerd Font"
FontSize="13"
KeyboardSize="0.4"
RoundCorners="20"

Locale=""
HourFormat="HH:mm"
DateFormat="dddd d MMMM"
HeaderText=""

Background="Backgrounds/arch_wallpaper.jpg"
BackgroundPlaceholder=""
BackgroundSpeed=""
PauseBackground=""
DimBackground="0.5"
CropBackground="true"
BackgroundHorizontalAlignment="center"
BackgroundVerticalAlignment="center"

HeaderTextColor="#cdd6f4"
DateTextColor="#cdd6f4"
TimeTextColor="#cdd6f4"

FormBackgroundColor="#1e1e2e"
BackgroundColor="#1e1e2e"
DimBackgroundColor="#1e1e2e"

LoginFieldBackgroundColor="#313244"
PasswordFieldBackgroundColor="#313244"
LoginFieldTextColor="#cdd6f4"
PasswordFieldTextColor="#cdd6f4"
UserIconColor="#cdd6f4"
PasswordIconColor="#cdd6f4"

PlaceholderTextColor="#6c7086"
WarningColor="#45475a"

LoginButtonTextColor="#1e1e2e"
LoginButtonBackgroundColor="#cdd6f4"
SystemButtonsIconsColor="#cdd6f4"
SessionButtonTextColor="#cdd6f4"
VirtualKeyboardButtonTextColor="#cdd6f4"

DropdownTextColor="#cdd6f4"
DropdownSelectedBackgroundColor="#45475a"
DropdownBackgroundColor="#1e1e2e"

HighlightTextColor="#1e1e2e"
HighlightBackgroundColor="#cdd6f4"
HighlightBorderColor="#cdd6f4"

HoverUserIconColor="#89b4fa"
HoverPasswordIconColor="#89b4fa"
HoverSystemButtonsIconsColor="#89b4fa"
HoverSessionButtonTextColor="#89b4fa"
HoverVirtualKeyboardButtonTextColor="#89b4fa"

PartialBlur=""
FullBlur="true"
BlurMax="64"
Blur="1.0"

HaveFormBackground="true"
FormPosition="center"

VirtualKeyboardPosition="center"

HideVirtualKeyboard="true"
HideSystemButtons="false"
HideLoginButton="false"

ForceLastUser="true"
PasswordFocus="true"
HideCompletePassword="true"
AllowEmptyPassword="false"
AllowUppercaseLettersInUsernames="false"
BypassSystemButtonsChecks="false"
RightToLeftLayout="false"

TranslatePlaceholderUsername=""
TranslatePlaceholderPassword=""
TranslateLogin=""
TranslateLoginFailedWarning=""
TranslateCapslockWarning=""
TranslateSuspend=""
TranslateHibernate=""
TranslateReboot=""
TranslateShutdown=""
TranslateSessionSelection=""
TranslateVirtualKeyboardButtonOn=""
TranslateVirtualKeyboardButtonOff=""
SDDMTHEME

        # Point theme at catppuccin_mocha config
        sudo sed -i 's|ConfigFile=.*|ConfigFile=Themes/catppuccin_mocha.conf|' \
            "$THEME_DIR/metadata.desktop"

        # Set SDDM to use this theme
        sudo mkdir -p /etc/sddm.conf.d
        sudo tee /etc/sddm.conf.d/theme.conf > /dev/null << 'SDDMCONF'
[Theme]
Current=sddm-astronaut-theme
SDDMCONF

        echo "Catppuccin Mocha SDDM theme configured"
    else
        echo "WARNING: sddm-astronaut-theme directory not found, skipping theme config"
    fi
fi

sudo systemctl enable sddm
echo "SDDM installed and enabled"

# ============================================================================
# STEP 13/16: Bootstrap Git Config + Clone and Apply Dotfiles
# ============================================================================
echo ""
echo "========================================================================"
echo "STEP 13/16: Cloning and Applying Dotfiles"
echo "========================================================================"

# Write a minimal gitconfig first so git clone works with correct identity.
# This will be overwritten by the dotfiles checkout with the full config.
# (The actual file backups for restore-after-checkout happened already, up in
# the SAFETY GUARDS section, covering more than just ~/.gitconfig.)
if [ "$PRESERVE_GITCONFIG" = true ]; then
    echo "GUARD: preserving existing two-account ~/.gitconfig — skipping bootstrap identity."
else
    if [ -z "$GIT_USER_NAME" ]; then
        printf "Git user.name for commits: "
        read -r GIT_USER_NAME
    fi
    if [ -z "$GIT_USER_EMAIL" ]; then
        printf "Git user.email for commits: "
        read -r GIT_USER_EMAIL
    fi
    echo "Writing bootstrap git config..."
    git config --global user.name "$GIT_USER_NAME"
    git config --global user.email "$GIT_USER_EMAIL"
fi

# Force the personal key for the dotfiles clone (it's a sproko repo), so this
# works even where github.com defaults to a different account's key.
DOTFILES_GIT_SSH=""
if [ -n "$DOTFILES_SSH_KEY" ] && [ -f "$DOTFILES_SSH_KEY" ]; then
    DOTFILES_GIT_SSH="ssh -i $DOTFILES_SSH_KEY -o IdentitiesOnly=yes -o IdentityAgent=none"
fi

# Resolve which dotfiles branch to check out. If not set via --dotfiles-branch,
# list the remote branches and prompt (this machine's likely branch is suggested).
if [ -z "$DOTFILES_BRANCH" ]; then
    echo "Fetching available dotfiles branches from $DOTFILES_REPO ..."
    mapfile -t DF_BRANCHES < <(GIT_SSH_COMMAND="$DOTFILES_GIT_SSH" \
        git ls-remote --heads "$DOTFILES_REPO" 2>/dev/null | sed 's#.*refs/heads/##')
    if [ "${#DF_BRANCHES[@]}" -eq 0 ]; then
        echo "ERROR: could not list branches (check SSH access to $DOTFILES_REPO)."
        exit 1
    fi

    # Suggest a sensible default for this machine.
    DF_DEFAULT=""
    if pacman -Q cachyos-hypr-noctalia &>/dev/null; then
        for b in "${DF_BRANCHES[@]}"; do [ "$b" = "noctalia-cachyos" ] && DF_DEFAULT="$b"; done
    fi

    echo ""
    echo "Available dotfiles branches:"
    idx=1
    for b in "${DF_BRANCHES[@]}"; do
        suffix=""; [ "$b" = "$DF_DEFAULT" ] && suffix="  <- suggested for this machine"
        printf "  %d) %s%s\n" "$idx" "$b" "$suffix"
        idx=$((idx + 1))
    done

    while [ -z "$DOTFILES_BRANCH" ]; do
        if [ -n "$DF_DEFAULT" ]; then
            printf "Select branch number, type a name, or Enter for '%s': " "$DF_DEFAULT"
        else
            printf "Select branch number or type a name: "
        fi
        read -r sel
        if [ -z "$sel" ] && [ -n "$DF_DEFAULT" ]; then
            DOTFILES_BRANCH="$DF_DEFAULT"
        elif [[ "$sel" =~ ^[0-9]+$ ]]; then
            if [ "$sel" -ge 1 ] && [ "$sel" -le "${#DF_BRANCHES[@]}" ]; then
                DOTFILES_BRANCH="${DF_BRANCHES[$((sel - 1))]}"
            else
                echo "  '$sel' is out of range — try again."
            fi
        elif [ -n "$sel" ]; then
            DOTFILES_BRANCH="$sel"   # typed a branch name directly
        fi
    done
    echo "Using dotfiles branch: $DOTFILES_BRANCH"
fi

# Clone dotfiles bare repo
if [ -d "$HOME/.dotfiles" ]; then
    echo "Dotfiles bare repo already exists at $HOME/.dotfiles — skipping clone."
else
    echo "Cloning dotfiles bare repo from $DOTFILES_REPO ..."
    GIT_SSH_COMMAND="$DOTFILES_GIT_SSH" git clone --bare "$DOTFILES_REPO" "$HOME/.dotfiles"
fi

echo "Checking out branch: $DOTFILES_BRANCH ..."
if ! git --git-dir="$HOME/.dotfiles" --work-tree="$HOME" checkout "$DOTFILES_BRANCH" 2>/dev/null; then
    echo ""
    echo "WARNING: Checkout had conflicts. Backing up conflicting files and retrying..."
    BACKUP_DIR="$HOME/.dotfiles-backup-$(date +%Y%m%d%H%M%S)"
    mkdir -p "$BACKUP_DIR"
    CONFLICT_LIST=$(git --git-dir="$HOME/.dotfiles" --work-tree="$HOME" checkout "$DOTFILES_BRANCH" 2>&1 \
        | grep "^\s" | awk '{print $1}')
    for conflict_file in $CONFLICT_LIST; do
        target_dir="$BACKUP_DIR/$(dirname "$conflict_file")"
        mkdir -p "$target_dir"
        mv "$HOME/$conflict_file" "$target_dir/" 2>/dev/null || true
    done
    git --git-dir="$HOME/.dotfiles" --work-tree="$HOME" checkout "$DOTFILES_BRANCH"
    echo "Conflicting files backed up to: $BACKUP_DIR"
fi

# The full ~/.gitconfig (with delta, http retry, etc.) is now restored from dotfiles.

# Hide untracked files from dotfiles status output
git --git-dir="$HOME/.dotfiles" --work-tree="$HOME" config --local status.showUntrackedFiles no

# Pin the personal key on the dotfiles repo so fetch/push/pull (and the
# 'dotfiles' alias) always talk to sproko regardless of the global git config.
if [ -n "$DOTFILES_GIT_SSH" ]; then
    git --git-dir="$HOME/.dotfiles" --work-tree="$HOME" config --local core.sshCommand "$DOTFILES_GIT_SSH"
fi

# Add fetch refspec so 'git fetch' retrieves all remote branches (bare clones omit this)
git --git-dir="$HOME/.dotfiles" --work-tree="$HOME" config remote.origin.fetch '+refs/heads/*:refs/remotes/origin/*'
git --git-dir="$HOME/.dotfiles" --work-tree="$HOME" fetch origin

# Track the remote branch so 'dotfiles push/pull' works without explicit remote/branch
git --git-dir="$HOME/.dotfiles" --work-tree="$HOME" branch --set-upstream-to="origin/$DOTFILES_BRANCH" "$DOTFILES_BRANCH"

echo "Dotfiles applied from branch: $DOTFILES_BRANCH"

# Restore the two-account git/ssh/fish files, in case the dotfiles checkout
# just overwrote any of them (or added them fresh under a different version).
if [ "$PRESERVE_GITCONFIG" = true ]; then
    for f in "${DUAL_ACCOUNT_FILES[@]}"; do
        backup="$DUAL_ACCOUNT_PRESERVE_DIR/$f"
        if [ -f "$backup" ]; then
            mkdir -p "$(dirname "$f")"
            cp -a "$backup" "$f"
        fi
    done
    rm -rf "$DUAL_ACCOUNT_PRESERVE_DIR"
    echo "GUARD: restored two-account git/ssh/fish setup (dotfiles versions of these files, if any, were skipped)."
fi

# ============================================================================
# HELPER: detect classic (hyprland.conf) vs Lua/Noctalia (hyprland.lua +
# config/autostart.lua) config scheme, and a way to inject an autostart
# command into whichever one this machine/dotfiles branch uses.
# ============================================================================
HYPR_CONF_DIR="$HOME/.config/hypr"
HYPRLAND_CONF="$HYPR_CONF_DIR/hyprland.conf"
HYPR_AUTOSTART_LUA="$HYPR_CONF_DIR/config/autostart.lua"
HYPR_LUA_SCHEME=false
[ -f "$HYPR_CONF_DIR/hyprland.lua" ] && HYPR_LUA_SCHEME=true

# Insert `hl.exec_cmd("<cmd>")` into config/autostart.lua's hl.on("hyprland.start", ...)
# block, right before its closing `end)`. Skips if already present (idempotent)
# or if the file doesn't look like the expected shape (prints a warning instead
# of guessing at a rewrite).
hypr_lua_autostart_add() {
    local cmd="$1"
    if [ ! -f "$HYPR_AUTOSTART_LUA" ]; then
        echo "WARNING: $HYPR_AUTOSTART_LUA not found — add manually: hl.exec_cmd(\"$cmd\")"
        return
    fi
    if grep -qF "$cmd" "$HYPR_AUTOSTART_LUA"; then
        echo "  already present in autostart.lua: $cmd"
        return
    fi
    awk -v line="    hl.exec_cmd(\"$cmd\")" '
        { buf[NR] = $0; if ($0 == "end)") last = NR }
        END {
            for (i = 1; i <= NR; i++) {
                if (i == last) print line
                print buf[i]
            }
        }
    ' "$HYPR_AUTOSTART_LUA" > "$HYPR_AUTOSTART_LUA.tmp" && mv "$HYPR_AUTOSTART_LUA.tmp" "$HYPR_AUTOSTART_LUA"
    if grep -qF "$cmd" "$HYPR_AUTOSTART_LUA"; then
        echo "  added to autostart.lua: hl.exec_cmd(\"$cmd\")"
    else
        echo "WARNING: couldn't find a closing 'end)' to insert before in $HYPR_AUTOSTART_LUA"
        echo "         add manually: hl.exec_cmd(\"$cmd\")"
    fi
}

# ============================================================================
# CONFIGURATION: desktop wallpaper
# ============================================================================
echo ""
echo "========================================================================"
echo "CONFIGURATION: Setting up desktop wallpaper"
echo "========================================================================"
WALLPAPER_DEST="$HOME/Pictures/arch_wallpaper.jpg"

# Fall back to source image if Pictures copy didn't happen (e.g. SDDM extras disabled)
if [ ! -f "$WALLPAPER_DEST" ] && [ -f "$WALLPAPER_SOURCE" ]; then
    mkdir -p "$HOME/Pictures"
    cp "$WALLPAPER_SOURCE" "$WALLPAPER_DEST"
fi

if [ "$HYPR_LUA_SCHEME" = true ]; then
    # Noctalia (this repo's noctalia-cachyos branch) has no dependency on
    # hyprpaper/swww — it renders its own wallpaper and has its own wallpaper
    # picker panel (see the "panel-toggle wallpaper" bind). Wiring up hyprpaper
    # here would just be a second, unused wallpaper daemon, so skip it and
    # leave the image in ~/Pictures for picking via Noctalia's own panel.
    echo "Lua/Noctalia hypr config detected — skipping hyprpaper (Noctalia manages its own wallpaper)."
    echo "Wallpaper image available at $WALLPAPER_DEST for Noctalia's wallpaper panel."
else
    HYPRPAPER_CONF="$HYPR_CONF_DIR/hyprpaper.conf"
    if [ ! -f "$HYPRPAPER_CONF" ]; then
        mkdir -p "$HYPR_CONF_DIR"
        cat > "$HYPRPAPER_CONF" << HYPRPAPER
preload = $WALLPAPER_DEST
wallpaper = ,$WALLPAPER_DEST
splash = false
HYPRPAPER
        echo "hyprpaper.conf written → $HYPRPAPER_CONF"
    else
        echo "hyprpaper.conf already exists (from dotfiles) — skipping"
    fi

    if [ -f "$HYPRLAND_CONF" ] && ! grep -q "exec-once = hyprpaper" "$HYPRLAND_CONF"; then
        printf '\n# Wallpaper daemon\nexec-once = hyprpaper\n' >> "$HYPRLAND_CONF"
        echo "exec-once = hyprpaper added to hyprland.conf"
    fi
fi

# ============================================================================
# CONFIGURATION: zshrc + aliases
# ============================================================================
echo ""
echo "========================================================================"
echo "CONFIGURATION: Writing ~/.zshrc"
echo "========================================================================"

if [ "$INSTALL_OMZ" = true ]; then
    # Back up an existing ~/.zshrc rather than clobbering it silently.
    if [ -f ~/.zshrc ]; then
        cp -a ~/.zshrc "$HOME/.zshrc.bak.$(date +%Y%m%d%H%M%S)"
        echo "GUARD: backed up existing ~/.zshrc"
    fi
    cat > ~/.zshrc << 'ZSHRC'
export ZSH="$HOME/.oh-my-zsh"

ZSH_THEME="robbyrussell"

plugins=(git ssh-agent)

source $ZSH/oh-my-zsh.sh

# .NET paths
export DOTNET_ROOT=/usr/share/dotnet
export PATH=$PATH:$DOTNET_ROOT:$HOME/.dotnet/tools

# Local bin path
export PATH="$HOME/.local/bin:$PATH"

# SSH agent configuration
zstyle :omz:plugins:ssh-agent identities id_ed25519

# Dotfiles bare-repo alias
alias dotfiles='git --git-dir=$HOME/.dotfiles --work-tree=$HOME'

# Useful aliases
alias ll='ls -lah'
alias gs='git status'
alias gp='git pull'

if command -v eza &>/dev/null; then
    alias ls='eza'
    alias ll='eza -lah'
fi

if command -v bat &>/dev/null; then
    alias cat='bat'
fi

# Wayland / Hyprland helpers
alias hypr-reload='hyprctl reload'
alias hypr-log='journalctl --user -u hyprland -n 50 --no-pager'
ZSHRC

    if [ "$INSTALL_STARSHIP" = true ]; then
        echo 'eval "$(starship init zsh)"' >> ~/.zshrc
    fi

    # Only change the login shell if it's still a default (bash/sh). If the user
    # already runs fish/zsh/etc., leave it alone. sudo avoids an interactive prompt.
    case "$CURRENT_LOGIN_SHELL" in
        */bash|*/sh|"")
            sudo chsh -s /usr/bin/zsh "$USER"
            echo "Default shell changed to zsh (will take effect on next login)"
            ;;
        *)
            echo "GUARD: login shell is already '$CURRENT_LOGIN_SHELL' — leaving it unchanged."
            ;;
    esac
fi

# Add Bluetooth auto-connect if a MAC is configured and not already present
if [ -n "$BLUETOOTH_DEVICE_MAC" ]; then
    if [ "$HYPR_LUA_SCHEME" = true ]; then
        hypr_lua_autostart_add "bluetoothctl connect ${BLUETOOTH_DEVICE_MAC}"
    elif [ -f "$HYPRLAND_CONF" ] && ! grep -q "$BLUETOOTH_DEVICE_MAC" "$HYPRLAND_CONF"; then
        echo "" >> "$HYPRLAND_CONF"
        echo "# Auto-connect Bluetooth device on login" >> "$HYPRLAND_CONF"
        echo "exec-once = bluetoothctl connect ${BLUETOOTH_DEVICE_MAC}" >> "$HYPRLAND_CONF"
        echo "Bluetooth auto-connect entry added to hyprland.conf"
    fi
fi
fi # end --full only

# ============================================================================
# STEP 14/16: Enable System Services
# ============================================================================
echo ""
echo "========================================================================"
echo "STEP 14/16: Enabling System Services"
echo "========================================================================"
[ "$MODE" = "full" ] && sudo systemctl enable --now sddm 2>/dev/null || true
sudo systemctl enable --now NetworkManager  2>/dev/null || true
sudo systemctl enable --now sshd            2>/dev/null || true

[ "$INSTALL_DOCKER" = true ]    && sudo systemctl enable --now docker    2>/dev/null || true
[ "$INSTALL_BLUETOOTH" = true ] && sudo systemctl enable --now bluetooth 2>/dev/null || true

echo "System services enabled"

# ============================================================================
# STEP 15/16: Install EF Core Tools
# ============================================================================
echo ""
echo "========================================================================"
echo "STEP 15/16: Installing Entity Framework Core CLI Tools"
echo "========================================================================"
if [ "$INSTALL_EF_TOOLS" = true ] && [ "$INSTALL_DOTNET_SDK" = true ]; then
    dotnet tool install --global dotnet-ef 2>/dev/null || dotnet tool update --global dotnet-ef

    if ! grep -q "/.dotnet/tools" ~/.zshrc 2>/dev/null; then
        echo 'export PATH="$PATH:$HOME/.dotnet/tools"' >> ~/.zshrc
    fi
    echo "EF Core tools installed"
else
    echo "Skipping EF Core tools (disabled in config or .NET SDK not installed)"
fi

# ============================================================================
# STEP 16/16: Cleanup and Final Summary
# ============================================================================
echo ""
echo "========================================================================"
echo "STEP 16/16: Cleaning Up"
echo "========================================================================"
sudo pacman -Sc --noconfirm 2>/dev/null || true
echo "Package cache cleaned"

echo ""
echo "╔════════════════════════════════════════════════════════════════╗"
echo "║                    INSTALLATION COMPLETE!                      ║"
echo "╚════════════════════════════════════════════════════════════════╝"
echo ""
echo "Summary of installed components:"
if [ "$MODE" = "full" ]; then
echo "  + Hyprland (Wayland compositor) + waybar + wofi + alacritty"
echo "  + swaync + swww + hyprlock + hypridle + hyprpaper + wlogout"
echo "  + cliphist + grim + slurp + polkit-kde-agent"
[ "$INSTALL_HYPRLAND_EXTRAS" = true ]  && echo "  + wlopm (screen power management)"
fi
echo "  + Development tools (git, base-devel, neovim, tmux, cmake, curl, wget)"
[ "$INSTALL_OPTIONAL_TOOLS" = true ]   && echo "  + Modern CLI tools (fzf, ripgrep, fd, bat, eza, lazygit)"
[ "$INSTALL_DOTNET_SDK" = true ]       && echo "  + .NET ${INSTALL_DOTNET_VERSION} SDK"
[ "$INSTALL_DOCKER" = true ]           && echo "  + Docker Engine + docker-compose"
[ "$INSTALL_EF_TOOLS" = true ] && [ "$INSTALL_DOTNET_SDK" = true ] && echo "  + Entity Framework Core CLI tools"
if [ "$MODE" = "full" ]; then
echo "  + PipeWire (pipewire-pulse, wireplumber, pavucontrol)"
[ "$INSTALL_BLUETOOTH" = true ]        && echo "  + Bluetooth (bluez, bluez-utils, blueman)"
[ "$INSTALL_NERD_FONTS" = true ]       && echo "  + Nerd Fonts (JetBrainsMono, Ubuntu, FiraCode)"
[ "$INSTALL_OMZ" = true ]              && echo "  + zsh + Oh-My-Zsh"
[ "$INSTALL_STARSHIP" = true ]         && echo "  + Starship prompt"
echo "  + SDDM display manager"
[ "$INSTALL_HYPRLAND_EXTRAS" = true ]  && echo "  + sddm-astronaut-theme (Catppuccin Mocha)"
echo ""
echo "Dotfiles configured:"
echo "  + Bare repo cloned to ~/.dotfiles (branch: ${DOTFILES_BRANCH})"
[ "$PRESERVE_GITCONFIG" = true ] \
    && echo "  + Existing two-account ~/.gitconfig preserved (dotfiles version skipped)" \
    || echo "  + Full ~/.gitconfig restored from dotfiles (delta, http retry, etc.)"
[ "$INSTALL_OMZ" = true ] && echo "  + zsh with Oh-My-Zsh and Starship (~/.zshrc)"
echo "  + 'dotfiles' alias available in zsh"
fi
echo ""

if [ "$MODE" = "full" ]; then
    echo "Next steps:"
    echo "  1. REBOOT your system:  sudo reboot"
    echo "  2. You will land on the SDDM login screen (Catppuccin Mocha theme)"
    echo "  3. Login with your username and password"
    echo "  4. Hyprland will start automatically"
    echo ""
    echo "Hyprland quick reference (Super = Windows/Meta key):"
    echo "  Super+Enter          = Open Alacritty terminal"
    echo "  Super+D              = Application launcher (wofi)"
    echo "  Super+Shift+Q        = Close window"
    echo "  Super+Shift+E        = Exit Hyprland (wlogout)"
    echo "  Super+backslash      = Lock screen (hyprlock)"
    echo "  Super+Shift+C        = Reload Hyprland config"
    echo "  Super+1 to Super+9   = Switch workspaces"
    echo "  Super+Shift+1 to 9   = Move window to workspace"
    echo "  Print                = Screenshot (full screen)"
    echo "  Super+Shift+S        = Screenshot (selection)"
    echo ""
    [ "$INSTALL_DOCKER" = true ] && echo "NOTE: For Docker without sudo, log out and back in!"
    echo ""
    echo "Dotfiles alias:"
    echo "  dotfiles status"
    echo "  dotfiles add ~/.config/hypr/hyprland.conf"
    echo "  dotfiles commit -m 'update config'"
    echo "  dotfiles push"
    echo ""
    echo "Enjoy your new CachyOS Hyprland development environment!"
else
    echo "Next steps:"
    [ "$INSTALL_DOCKER" = true ] && echo "  - Docker: log out and back in so the 'docker' group takes effect."
    [ "$INSTALL_DOTNET_SDK" = true ] && echo "  - .NET: open a new shell (PATH now includes ~/.dotnet/tools for EF etc.)."
    echo "  - Dev tools installed. No reboot required."
    echo ""
    echo "Dev environment ready."
fi
