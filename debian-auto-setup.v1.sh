#!/bin/bash
# Debian 13 Unattended Setup Script - Complete i3 Development Environment
# Based on debian-setup-guide.md
# Run as regular user (will prompt for sudo password once at start)

set -e  # Exit on error

# ============================================================================
# CONFIGURATION - Modify these to customize your installation
# ============================================================================

# User configuration
INSTALL_DOTNET_SDK=true           # Install .NET 8 SDK
INSTALL_DOTNET_VERSION="8.0"      # .NET version (8.0, 9.0, or 10.0)
INSTALL_MONO=true                 # Install Mono for .NET Framework compatibility
INSTALL_DOCKER=true               # Install Docker Engine
INSTALL_EF_TOOLS=true             # Install Entity Framework CLI tools
INSTALL_ZSH_STARSHIP=true         # Install zsh and Starship prompt
INSTALL_NERD_FONTS=true           # Install Nerd Fonts
INSTALL_AUDIO=true                # Install PulseAudio and audio tools
INSTALL_BLUETOOTH=true            # Install Bluetooth stack
INSTALL_LIGHTDM=true              # Install LightDM display manager
INSTALL_OPTIONAL_TOOLS=true       # Install fzf, ripgrep, bat, eza, etc.

# Nerd Fonts to install (space-separated list)
NERD_FONTS="JetBrainsMono UbuntuMono FiraCode"

# ============================================================================
# SCRIPT START - Do not modify below unless you know what you're doing
# ============================================================================

echo "╔════════════════════════════════════════════════════════════════╗"
echo "║  Debian 13 Unattended Setup - i3 Development Environment      ║"
echo "║  This will take 10-20 minutes depending on your connection    ║"
echo "╚════════════════════════════════════════════════════════════════╝"
echo ""

# Get sudo access upfront
echo "Please enter your sudo password to begin installation..."
sudo -v

# Keep sudo alive throughout the script
while true; do sudo -n true; sleep 60; kill -0 "$$" || exit; done 2>/dev/null &

echo ""
echo "========================================================================"
echo "STEP 1/14: Updating System Packages"
echo "========================================================================"
sudo apt update
sudo DEBIAN_FRONTEND=noninteractive apt upgrade -y

echo ""
echo "========================================================================"
echo "STEP 2/14: Installing i3 Window Manager and X Server"
echo "========================================================================"
sudo DEBIAN_FRONTEND=noninteractive apt install -y \
    i3 i3status i3lock xorg \
    rofi \
    thunar \
    firefox-esr

echo ""
echo "========================================================================"
echo "STEP 3/14: Installing Terminal Emulator (Alacritty)"
echo "========================================================================"
sudo DEBIAN_FRONTEND=noninteractive apt install -y alacritty

echo ""
echo "========================================================================"
echo "STEP 4/14: Installing Basic Utilities"
echo "========================================================================"
sudo DEBIAN_FRONTEND=noninteractive apt install -y \
    vim git curl wget htop tree unzip \
    build-essential gcc g++ gdb make cmake \
    git-lfs \
    neovim tmux direnv

if [ "$INSTALL_OPTIONAL_TOOLS" = true ]; then
    echo "Installing optional modern tools (fzf, ripgrep, bat, eza)..."
    sudo DEBIAN_FRONTEND=noninteractive apt install -y \
        fzf ripgrep fd-find bat eza || true
fi

echo ""
echo "========================================================================"
echo "STEP 5/14: Installing .NET SDK"
echo "========================================================================"
if [ "$INSTALL_DOTNET_SDK" = true ]; then
    # Remove any old config
    sudo rm -f /etc/apt/sources.list.d/msprod.list
    sudo rm -f /etc/apt/sources.list.d/microsoft-prod.list

    # Download and install Microsoft repository
    wget -q https://packages.microsoft.com/config/debian/13/packages-microsoft-prod.deb -O /tmp/packages-microsoft-prod.deb
    sudo dpkg -i /tmp/packages-microsoft-prod.deb
    rm /tmp/packages-microsoft-prod.deb

    sudo apt update
    sudo DEBIAN_FRONTEND=noninteractive apt install -y dotnet-sdk-${INSTALL_DOTNET_VERSION}

    echo ".NET SDK installed:"
    dotnet --version
else
    echo "Skipping .NET SDK installation (disabled in config)"
fi

echo ""
echo "========================================================================"
echo "STEP 6/14: Installing Mono (for .NET Framework compatibility)"
echo "========================================================================"
if [ "$INSTALL_MONO" = true ]; then
    sudo DEBIAN_FRONTEND=noninteractive apt install -y mono-complete
    echo "Mono installed:"
    mono --version | head -n 1
else
    echo "Skipping Mono installation (disabled in config)"
fi

echo ""
echo "========================================================================"
echo "STEP 7/14: Installing Docker Engine"
echo "========================================================================"
if [ "$INSTALL_DOCKER" = true ]; then
    sudo DEBIAN_FRONTEND=noninteractive apt install -y docker.io docker-compose-v2
    sudo systemctl start docker
    sudo systemctl enable docker
    sudo usermod -aG docker $USER
    echo "Docker installed. NOTE: Log out and back in for docker group to take effect"
else
    echo "Skipping Docker installation (disabled in config)"
fi

echo ""
echo "========================================================================"
echo "STEP 8/14: Installing Audio Stack (PulseAudio)"
echo "========================================================================"
if [ "$INSTALL_AUDIO" = true ]; then
    sudo DEBIAN_FRONTEND=noninteractive apt install -y \
        pulseaudio pavucontrol alsa-utils pasystray

    # Start PulseAudio
    pulseaudio --check || pulseaudio --start
    echo "Audio stack installed"
else
    echo "Skipping audio installation (disabled in config)"
fi

echo ""
echo "========================================================================"
echo "STEP 9/14: Installing Bluetooth Stack"
echo "========================================================================"
if [ "$INSTALL_BLUETOOTH" = true ]; then
    sudo DEBIAN_FRONTEND=noninteractive apt install -y \
        bluetooth bluez bluez-tools pulseaudio-module-bluetooth \
        firmware-realtek firmware-atheros firmware-iwlwifi \
        blueman

    sudo systemctl start bluetooth
    sudo systemctl enable bluetooth
    echo "Bluetooth stack installed"
else
    echo "Skipping Bluetooth installation (disabled in config)"
fi

echo ""
echo "========================================================================"
echo "STEP 10/14: Installing Network Manager"
echo "========================================================================"
sudo DEBIAN_FRONTEND=noninteractive apt install -y network-manager network-manager-gnome
sudo systemctl enable NetworkManager
sudo systemctl start NetworkManager

echo ""
echo "========================================================================"
echo "STEP 11/14: Installing Clipboard Manager and Additional Tools"
echo "========================================================================"
sudo DEBIAN_FRONTEND=noninteractive apt install -y \
    diodon autocutsel \
    feh scrot brightnessctl

echo ""
echo "========================================================================"
echo "STEP 12/14: Installing Nerd Fonts"
echo "========================================================================"
if [ "$INSTALL_NERD_FONTS" = true ]; then
    mkdir -p ~/.local/share/fonts
    cd ~/.local/share/fonts

    NERD_FONT_VERSION="v3.1.1"

    for font in $NERD_FONTS; do
        echo "Downloading $font Nerd Font..."
        wget -q --show-progress https://github.com/ryanoasis/nerd-fonts/releases/download/${NERD_FONT_VERSION}/${font}.zip -O ${font}.zip
        unzip -q -o ${font}.zip
        rm ${font}.zip
    done

    # Remove Windows-specific files
    rm -f *Windows*.ttf

    # Rebuild font cache
    fc-cache -fv

    echo "Nerd Fonts installed:"
    fc-list | grep -i "Nerd Font" | cut -d: -f2 | sort -u | head -n 5

    cd - > /dev/null
else
    echo "Skipping Nerd Fonts installation (disabled in config)"
fi

echo ""
echo "========================================================================"
echo "STEP 13/14: Installing zsh and Starship Prompt"
echo "========================================================================"
if [ "$INSTALL_ZSH_STARSHIP" = true ]; then
    sudo DEBIAN_FRONTEND=noninteractive apt install -y zsh

    # Install Starship
    echo "Installing Starship prompt..."
    curl -sS https://starship.rs/install.sh | sh -s -- -y

    echo "zsh and Starship installed"
else
    echo "Skipping zsh/Starship installation (disabled in config)"
fi

echo ""
echo "========================================================================"
echo "STEP 14/14: Installing LightDM Display Manager"
echo "========================================================================"
if [ "$INSTALL_LIGHTDM" = true ]; then
    sudo DEBIAN_FRONTEND=noninteractive apt install -y lightdm
    sudo systemctl enable lightdm
    echo "LightDM installed and enabled"
else
    echo "Skipping LightDM installation (disabled in config)"
fi

echo ""
echo "========================================================================"
echo "CONFIGURATION: Setting up dotfiles and configs"
echo "========================================================================"

# Create i3 config directory
mkdir -p ~/.config/i3
mkdir -p ~/.config/i3status
mkdir -p ~/.config/alacritty

# Create basic i3 config if it doesn't exist
if [ ! -f ~/.config/i3/config ]; then
    echo "Generating i3 config..."
    i3-config-wizard -o ~/.config/i3/config || true
fi

# Create Alacritty config
echo "Creating Alacritty configuration..."
cat > ~/.config/alacritty/alacritty.toml << 'EOF'
[font]
size = 14.0

[font.normal]
family = "JetBrainsMono Nerd Font"
style = "Regular"

[font.bold]
family = "JetBrainsMono Nerd Font"
style = "Bold"

[font.italic]
family = "JetBrainsMono Nerd Font"
style = "Italic"

[colors.primary]
background = "#1e1e1e"
foreground = "#d4d4d4"

[window]
padding.x = 10
padding.y = 10
EOF

# Create i3status config
echo "Creating i3status configuration..."
cat > ~/.config/i3status/config << 'EOF'
general {
    colors = true
    interval = 5
}

order += "cpu_usage"
order += "disk /"
order += "memory"
order += "ethernet _first_"
order += "tztime local"

cpu_usage {
    format = "CPU: %usage"
}

disk "/" {
    format = "HDD: %avail"
}

memory {
    format = "RAM: %used / %total"
    threshold_degraded = "10%"
    format_degraded = "RAM: %free"
}

ethernet _first_ {
    format_up = "E: %ip (%speed)"
    format_down = "E: down"
}

tztime local {
    format = "%Y-%m-%d %H:%M"
}
EOF

# Configure zsh with Starship if installed
if [ "$INSTALL_ZSH_STARSHIP" = true ]; then
    echo "Configuring zsh with Starship..."
    cat > ~/.zshrc << 'EOF'
# Starship prompt
eval "$(starship init zsh)"

# .NET paths
export DOTNET_ROOT=$HOME/.dotnet
export PATH=$PATH:$DOTNET_ROOT:$DOTNET_ROOT/tools

# Useful aliases
alias ll='ls -lah'
alias gs='git status'
alias gp='git pull'

# Use modern tools if available
if command -v eza &> /dev/null; then
    alias ls='eza'
    alias ll='eza -lah'
fi

if command -v bat &> /dev/null; then
    alias cat='bat'
fi
EOF

    # Change default shell to zsh
    chsh -s /usr/bin/zsh
    echo "Default shell changed to zsh (will take effect on next login)"
fi

# Add i3 customizations to config
echo "Adding i3 customizations..."
cat >> ~/.config/i3/config << 'EOF'

# ===================================================================
# Custom Configuration Added by debian-auto-setup.sh
# ===================================================================

# Use Alacritty as default terminal
bindsym $mod+Return exec alacritty

# Use rofi instead of dmenu
bindsym $mod+d exec --no-startup-id rofi -show drun

# Lock screen
bindsym $mod+l exec --no-startup-id i3lock -c 000000

# Screenshot
bindsym Print exec --no-startup-id scrot '%Y-%m-%d_%H-%M-%S.png' -e 'mv $f ~/Pictures/'

# Volume controls
bindsym XF86AudioRaiseVolume exec --no-startup-id pactl set-sink-volume @DEFAULT_SINK@ +5%
bindsym XF86AudioLowerVolume exec --no-startup-id pactl set-sink-volume @DEFAULT_SINK@ -5%
bindsym XF86AudioMute exec --no-startup-id pactl set-sink-mute @DEFAULT_SINK@ toggle

# Brightness controls
bindsym XF86MonBrightnessUp exec --no-startup-id brightnessctl set +10%
bindsym XF86MonBrightnessDown exec --no-startup-id brightnessctl set 10%-

# Autostart applications
exec --no-startup-id nm-applet
exec --no-startup-id pasystray
exec --no-startup-id blueman-applet
exec --no-startup-id diodon
exec --no-startup-id autocutsel -fork
exec --no-startup-id autocutsel -selection PRIMARY -fork

# Use custom i3status config
bar {
    status_command i3status -c ~/.config/i3status/config
    position top
    tray_output primary
    tray_padding 2

    colors {
        background #000000
        statusline #ffffff
        separator #666666
    }
}
EOF

# Install EF Core tools if .NET is installed
if [ "$INSTALL_EF_TOOLS" = true ] && [ "$INSTALL_DOTNET_SDK" = true ]; then
    echo ""
    echo "========================================================================"
    echo "Installing Entity Framework Core CLI Tools"
    echo "========================================================================"
    dotnet tool install --global dotnet-ef

    # Ensure tools are in PATH
    if ! grep -q "/.dotnet/tools" ~/.bashrc 2>/dev/null; then
        echo 'export PATH="$PATH:$HOME/.dotnet/tools"' >> ~/.bashrc
    fi

    if [ -f ~/.zshrc ] && ! grep -q "/.dotnet/tools" ~/.zshrc 2>/dev/null; then
        echo 'export PATH="$PATH:$HOME/.dotnet/tools"' >> ~/.zshrc
    fi
fi

echo ""
echo "========================================================================"
echo "CLEANUP: Removing unnecessary packages"
echo "========================================================================"
sudo apt autoremove -y
sudo apt clean

echo ""
echo "╔════════════════════════════════════════════════════════════════╗"
echo "║                    INSTALLATION COMPLETE!                      ║"
echo "╚════════════════════════════════════════════════════════════════╝"
echo ""
echo "Summary of installed components:"
echo "  ✓ i3 Window Manager + X Server"
echo "  ✓ Alacritty Terminal"
echo "  ✓ Firefox ESR Browser"
echo "  ✓ Development Tools (gcc, g++, make, cmake, git)"
[ "$INSTALL_DOTNET_SDK" = true ] && echo "  ✓ .NET ${INSTALL_DOTNET_VERSION} SDK"
[ "$INSTALL_MONO" = true ] && echo "  ✓ Mono (for .NET Framework compatibility)"
[ "$INSTALL_DOCKER" = true ] && echo "  ✓ Docker Engine"
[ "$INSTALL_EF_TOOLS" = true ] && [ "$INSTALL_DOTNET_SDK" = true ] && echo "  ✓ Entity Framework Core CLI Tools"
[ "$INSTALL_AUDIO" = true ] && echo "  ✓ PulseAudio + pavucontrol"
[ "$INSTALL_BLUETOOTH" = true ] && echo "  ✓ Bluetooth + Blueman"
[ "$INSTALL_NERD_FONTS" = true ] && echo "  ✓ Nerd Fonts (JetBrainsMono, UbuntuMono, FiraCode)"
[ "$INSTALL_ZSH_STARSHIP" = true ] && echo "  ✓ zsh + Starship prompt"
[ "$INSTALL_LIGHTDM" = true ] && echo "  ✓ LightDM Display Manager"
echo ""
echo "Next steps:"
echo "  1. REBOOT your system: sudo reboot"
echo "  2. You'll see the LightDM login screen"
echo "  3. Login with your username and password"
echo "  4. i3 will start automatically!"
echo ""
echo "Basic i3 shortcuts (Mod = Windows/Super key):"
echo "  Mod+Enter       = Open Alacritty terminal"
echo "  Mod+d           = Application launcher (rofi)"
echo "  Mod+Shift+q     = Close window"
echo "  Mod+Shift+r     = Reload i3 config"
echo "  Mod+Shift+e     = Exit i3"
echo "  Mod+1 to Mod+9  = Switch workspaces"
echo ""
echo "Configuration files created:"
echo "  ~/.config/i3/config"
echo "  ~/.config/i3status/config"
echo "  ~/.config/alacritty/alacritty.toml"
[ "$INSTALL_ZSH_STARSHIP" = true ] && echo "  ~/.zshrc"
echo ""
[ "$INSTALL_DOCKER" = true ] && echo "NOTE: For Docker to work without sudo, log out and back in!"
echo ""
echo "For more customization, see: ~/debian-setup-guide.md"
echo ""
echo "Enjoy your new Debian i3 development environment! 🚀"
