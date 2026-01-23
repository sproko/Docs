#!/bin/bash
# Debian 13 Unattended Setup Script - Complete i3 Development Environment
# Based on debian-setup-guide.md with bundled dotfiles
# Run as regular user (will prompt for sudo password once at start)

set -e  # Exit on error

# ============================================================================
# CONFIGURATION - Modify these to customize your installation
# ============================================================================

# Git configuration (edit these for your own setup)
GIT_USER_NAME="Steve P"
GIT_USER_EMAIL="sprokopowich@proton.me"

# Bluetooth device to auto-connect (set to empty string to skip)
BLUETOOTH_DEVICE_MAC="db:b6:a2:f7:f6:e8"  # Set to "" if you don't have a bluetooth keyboard

# Installation options
INSTALL_DOTNET_SDK=true           # Install .NET 8 SDK
INSTALL_DOTNET_VERSION="10.0"      # .NET version (8.0, 9.0, or 10.0)
INSTALL_MONO=true                 # Install Mono for .NET Framework compatibility
INSTALL_DOCKER=true               # Install Docker Engine
INSTALL_EF_TOOLS=true             # Install Entity Framework CLI tools
INSTALL_OMZ=true                  # Install Oh-My-Zsh
INSTALL_STARSHIP=true             # Install Starship prompt (works with Oh-My-Zsh)
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
echo "STEP 1/15: Updating System Packages"
echo "========================================================================"
sudo apt update
sudo DEBIAN_FRONTEND=noninteractive apt upgrade -y

echo ""
echo "========================================================================"
echo "STEP 2/15: Installing i3 Window Manager and X Server"
echo "========================================================================"
sudo DEBIAN_FRONTEND=noninteractive apt install -y \
    i3 i3status i3lock xorg \
    rofi \
    thunar \
    firefox-esr \
    feh \
    xss-lock

echo ""
echo "========================================================================"
echo "STEP 3/15: Installing Terminal Emulator (Alacritty)"
echo "========================================================================"
sudo DEBIAN_FRONTEND=noninteractive apt install -y alacritty

echo ""
echo "========================================================================"
echo "STEP 4/15: Installing Basic Utilities"
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
echo "STEP 5/15: Installing .NET SDK"
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
echo "STEP 6/15: Installing Mono (for .NET Framework compatibility)"
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
echo "STEP 7/15: Installing Docker Engine"
echo "========================================================================"
if [ "$INSTALL_DOCKER" = true ]; then
    sudo DEBIAN_FRONTEND=noninteractive apt install -y docker.io docker-compose
    sudo systemctl start docker
    sudo systemctl enable docker
    sudo usermod -aG docker $USER
    echo "Docker installed. NOTE: Log out and back in for docker group to take effect"
else
    echo "Skipping Docker installation (disabled in config)"
fi

echo ""
echo "========================================================================"
echo "STEP 8/15: Installing Audio Stack (PulseAudio)"
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
echo "STEP 9/15: Installing Bluetooth Stack"
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
echo "STEP 10/15: Installing Network Manager"
echo "========================================================================"
sudo DEBIAN_FRONTEND=noninteractive apt install -y network-manager network-manager-gnome
sudo systemctl enable NetworkManager
sudo systemctl start NetworkManager

echo ""
echo "========================================================================"
echo "STEP 11/15: Installing Clipboard Manager and Additional Tools"
echo "========================================================================"
sudo DEBIAN_FRONTEND=noninteractive apt install -y \
    diodon autocutsel \
    scrot brightnessctl

echo ""
echo "========================================================================"
echo "STEP 12/15: Installing Nerd Fonts"
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
echo "STEP 13/15: Installing zsh and Oh-My-Zsh"
echo "========================================================================"
if [ "$INSTALL_OMZ" = true ]; then
    sudo DEBIAN_FRONTEND=noninteractive apt install -y zsh

    # Install Oh-My-Zsh (unattended)
    echo "Installing Oh-My-Zsh..."
    export RUNZSH=no
    export KEEP_ZSHRC=yes
    sh -c "$(curl -fsSL https://raw.githubusercontent.com/ohmyzsh/ohmyzsh/master/tools/install.sh)" "" --unattended

    echo "Oh-My-Zsh installed"
else
    echo "Skipping Oh-My-Zsh installation (disabled in config)"
fi

echo ""
echo "========================================================================"
echo "STEP 14/15: Installing Starship Prompt"
echo "========================================================================"
if [ "$INSTALL_STARSHIP" = true ]; then
    # Install Starship
    echo "Installing Starship prompt..."
    curl -sS https://starship.rs/install.sh | sh -s -- -y

    echo "Starship installed"
else
    echo "Skipping Starship installation (disabled in config)"
fi

echo ""
echo "========================================================================"
echo "STEP 15/15: Installing LightDM Display Manager"
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

# Create necessary directories
mkdir -p ~/.config/i3
mkdir -p ~/.config/i3status
mkdir -p ~/.config/alacritty
mkdir -p ~/.config/rofi
mkdir -p ~/Pictures

# ============================================================================
# Git Configuration
# ============================================================================
echo "Configuring Git..."
cat > ~/.gitconfig << EOF
[user]
	email = ${GIT_USER_EMAIL}
	name = ${GIT_USER_NAME}
[core]
	autocrlf = input
EOF

# ============================================================================
# X Resources Configuration
# ============================================================================
echo "Creating .Xresources..."
cat > ~/.Xresources << 'EOF'
Xft.dpi: 144
EOF

# ============================================================================
# i3 Configuration
# ============================================================================
echo "Creating i3 configuration..."
cat > ~/.config/i3/config << 'EOF'
# i3 config file (v4)
# Please see https://i3wm.org/docs/userguide.html for a complete reference!

set $mod Mod4

# Font for window titles
font pango:monospace 12
font pango:DejaVu Sans Mono 12

# Start XDG autostart .desktop files using dex
exec --no-startup-id dex --autostart --environment i3

# NetworkManager applet
exec --no-startup-id nm-applet

# Use pactl to adjust volume in PulseAudio
set $refresh_i3status killall -SIGUSR1 i3status

# Use Mouse+$mod to drag floating windows
floating_modifier $mod

# move tiling windows via drag & drop
tiling_drag modifier titlebar

# start a terminal
bindsym $mod+Return exec alacritty

# kill focused window
bindsym $mod+Shift+q kill

# start dmenu (rofi)
bindsym $mod+d exec --no-startup-id rofi -show drun

# change focus
bindsym $mod+j focus left
bindsym $mod+k focus down
bindsym $mod+l focus up
bindsym $mod+semicolon focus right

# alternatively, you can use the cursor keys:
bindsym $mod+Left focus left
bindsym $mod+Down focus down
bindsym $mod+Up focus up
bindsym $mod+Right focus right

# move focused window
bindsym $mod+Shift+j move left
bindsym $mod+Shift+k move down
bindsym $mod+Shift+l move up
bindsym $mod+Shift+semicolon move right

# alternatively, you can use the cursor keys:
bindsym $mod+Shift+Left move left
bindsym $mod+Shift+Down move down
bindsym $mod+Shift+Up move up
bindsym $mod+Shift+Right move right

# split in horizontal orientation
bindsym $mod+h split h

# split in vertical orientation
bindsym $mod+v split v

# enter fullscreen mode for the focused container
bindsym $mod+f fullscreen toggle

# change container layout (stacked, tabbed, toggle split)
bindsym $mod+s layout stacking
bindsym $mod+w layout tabbed
bindsym $mod+e layout toggle split

# toggle tiling / floating
bindsym $mod+Shift+space floating toggle

# change focus between tiling / floating windows
bindsym $mod+space focus mode_toggle

# focus the parent container
bindsym $mod+a focus parent

# Workspace assignments
assign [class="Rider"] 2
assign [class="jetbrains-rider"] 2
assign [class="GitKraken"] 3
assign [class="gitkraken"] 3
assign [class="firefox"] 4
assign [class="Firefox"] 4

# Workspace names
set $ws1 "1:term"
set $ws2 "2:rider"
set $ws3 "3:git"
set $ws4 "4:web"
set $ws5 "5"
set $ws6 "6"
set $ws7 "7"
set $ws8 "8"
set $ws9 "9"
set $ws10 "10"

# switch to workspace
bindsym $mod+1 workspace number $ws1
bindsym $mod+2 workspace number $ws2
bindsym $mod+3 workspace number $ws3
bindsym $mod+4 workspace number $ws4
bindsym $mod+5 workspace number $ws5
bindsym $mod+6 workspace number $ws6
bindsym $mod+7 workspace number $ws7
bindsym $mod+8 workspace number $ws8
bindsym $mod+9 workspace number $ws9
bindsym $mod+0 workspace number $ws10

# move focused container to workspace
bindsym $mod+Shift+1 move container to workspace number $ws1
bindsym $mod+Shift+2 move container to workspace number $ws2
bindsym $mod+Shift+3 move container to workspace number $ws3
bindsym $mod+Shift+4 move container to workspace number $ws4
bindsym $mod+Shift+5 move container to workspace number $ws5
bindsym $mod+Shift+6 move container to workspace number $ws6
bindsym $mod+Shift+7 move container to workspace number $ws7
bindsym $mod+Shift+8 move container to workspace number $ws8
bindsym $mod+Shift+9 move container to workspace number $ws9
bindsym $mod+Shift+0 move container to workspace number $ws10

# reload the configuration file
bindsym $mod+Shift+c reload

# restart i3 inplace
bindsym $mod+Shift+r restart

# exit i3
bindsym $mod+Shift+e exec "i3-nagbar -t warning -m 'You pressed the exit shortcut. Do you really want to exit i3? This will end your X session.' -B 'Yes, exit i3' 'i3-msg exit'"

# resize window mode
mode "resize" {
        bindsym j resize shrink width 10 px or 10 ppt
        bindsym k resize grow height 10 px or 10 ppt
        bindsym l resize shrink height 10 px or 10 ppt
        bindsym semicolon resize grow width 10 px or 10 ppt

        bindsym Left resize shrink width 10 px or 10 ppt
        bindsym Down resize grow height 10 px or 10 ppt
        bindsym Up resize shrink height 10 px or 10 ppt
        bindsym Right resize grow width 10 px or 10 ppt

        bindsym Return mode "default"
        bindsym Escape mode "default"
        bindsym $mod+r mode "default"
}

bindsym $mod+r mode "resize"

# i3bar configuration
bar {
        status_command i3status
	position bottom
	tray_output primary
	tray_padding 2
	colors {
        	background #000000
        	statusline #ffffff
        	separator #666666
    	}
}

# Set wallpaper
exec --no-startup-id feh --bg-scale ~/Pictures/wallpaper.jpg

# Lock screen shortcuts
bindsym $mod+\ exec --no-startup-id i3lock -c 000000
exec --no-startup-id xss-lock --transfer-sleep-lock -- i3lock --nofork

# Screenshot
bindsym Print exec --no-startup-id scrot '%Y-%m-%d_%H-%M-%S.png' -e 'mv $f ~/Pictures/'

# Volume controls
bindsym XF86AudioRaiseVolume exec --no-startup-id pactl set-sink-volume @DEFAULT_SINK@ +5%
bindsym XF86AudioLowerVolume exec --no-startup-id pactl set-sink-volume @DEFAULT_SINK@ -5%
bindsym XF86AudioMute exec --no-startup-id pactl set-sink-mute @DEFAULT_SINK@ toggle

# Brightness controls
bindsym XF86MonBrightnessUp exec --no-startup-id brightnessctl set +10%
bindsym XF86MonBrightnessDown exec --no-startup-id brightnessctl set 10%-

# Clipboard manager
exec --no-startup-id diodon
bindsym $mod+c exec --no-startup-id diodon
exec --no-startup-id autocutsel -fork
exec --no-startup-id autocutsel -selection PRIMARY -fork

# System tray applets
exec --no-startup-id pasystray
exec --no-startup-id blueman-applet
EOF

# Add bluetooth auto-connect if MAC is configured
if [ -n "$BLUETOOTH_DEVICE_MAC" ]; then
    echo "" >> ~/.config/i3/config
    echo "# Auto-connect Bluetooth device" >> ~/.config/i3/config
    echo "exec --no-startup-id bluetoothctl connect ${BLUETOOTH_DEVICE_MAC}" >> ~/.config/i3/config
fi

# Add auto-start applications if you want them (commented out by default)
cat >> ~/.config/i3/config << 'EOF'

# Auto-start applications on specific workspaces (uncomment to enable)
# exec --no-startup-id i3-msg 'workspace 1; exec alacritty'
# exec --no-startup-id i3-msg 'workspace 4; exec firefox'
EOF

# ============================================================================
# i3status Configuration
# ============================================================================
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

# ============================================================================
# Alacritty Configuration
# ============================================================================
echo "Creating Alacritty configuration..."
cat > ~/.config/alacritty/alacritty.toml << 'EOF'
[font]
size = 12.0

[font.normal]
family = "JetBrainsMono Nerd Font"
style = "Regular"

[font.bold]
family = "JetBrainsMono Nerd Font"
style = "Bold"

[colors.primary]
background = "#1e1e1e"  # Dark background
foreground = "#d4d4d4"  # Light text

[window]
opacity = 0.90 # Slight transparency (1.0 = opaque)
padding.x = 10
padding.y = 10

[cursor]
style = "Block"

[[keyboard.bindings]]
key = "Return"
mods = "Shift"
chars = "\u001b\r"
EOF

# ============================================================================
# Rofi Configuration
# ============================================================================
echo "Creating Rofi configuration..."
cat > ~/.config/rofi/config.rasi << 'EOF'
@theme "/usr/share/rofi/themes/Arc-Dark.rasi"
EOF

# ============================================================================
# zsh Configuration with Oh-My-Zsh and Starship
# ============================================================================
if [ "$INSTALL_OMZ" = true ]; then
    echo "Configuring zsh with Oh-My-Zsh and Starship..."
    cat > ~/.zshrc << 'EOF'
# Path to your Oh My Zsh installation.
export ZSH="$HOME/.oh-my-zsh"

# Set theme (robbyrussell is default, but we'll use Starship below)
ZSH_THEME="robbyrussell"

# Which plugins would you like to load?
# Standard plugins can be found in $ZSH/plugins/
# Custom plugins may be added to $ZSH_CUSTOM/plugins/
plugins=(git ssh-agent)

source $ZSH/oh-my-zsh.sh

# User configuration

# .NET paths
export DOTNET_ROOT=/usr/share/dotnet
export PATH=$PATH:$DOTNET_ROOT:$HOME/.dotnet/tools

# Local bin path
export PATH="$HOME/.local/bin:$PATH"

# SSH agent configuration
zstyle :omz:plugins:ssh-agent identities id_ed25519

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

# Enable Starship prompt (overrides Oh-My-Zsh theme)
EOF

    if [ "$INSTALL_STARSHIP" = true ]; then
        echo 'eval "$(starship init zsh)"' >> ~/.zshrc
    fi

    # Change default shell to zsh
    chsh -s /usr/bin/zsh
    echo "Default shell changed to zsh (will take effect on next login)"
fi

# Install EF Core tools if .NET is installed
if [ "$INSTALL_EF_TOOLS" = true ] && [ "$INSTALL_DOTNET_SDK" = true ]; then
    echo ""
    echo "========================================================================"
    echo "Installing Entity Framework Core CLI Tools"
    echo "========================================================================"
    dotnet tool install --global dotnet-ef || dotnet tool update --global dotnet-ef

    # Ensure tools are in PATH for bash
    if ! grep -q "/.dotnet/tools" ~/.bashrc 2>/dev/null; then
        echo 'export PATH="$PATH:$HOME/.dotnet/tools"' >> ~/.bashrc
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
echo "  ✓ Alacritty Terminal with JetBrainsMono Nerd Font"
echo "  ✓ Firefox ESR Browser"
echo "  ✓ Development Tools (gcc, g++, make, cmake, git)"
[ "$INSTALL_DOTNET_SDK" = true ] && echo "  ✓ .NET ${INSTALL_DOTNET_VERSION} SDK"
[ "$INSTALL_MONO" = true ] && echo "  ✓ Mono (for .NET Framework compatibility)"
[ "$INSTALL_DOCKER" = true ] && echo "  ✓ Docker Engine"
[ "$INSTALL_EF_TOOLS" = true ] && [ "$INSTALL_DOTNET_SDK" = true ] && echo "  ✓ Entity Framework Core CLI Tools"
[ "$INSTALL_AUDIO" = true ] && echo "  ✓ PulseAudio + pavucontrol"
[ "$INSTALL_BLUETOOTH" = true ] && echo "  ✓ Bluetooth + Blueman"
[ "$INSTALL_NERD_FONTS" = true ] && echo "  ✓ Nerd Fonts (JetBrainsMono, UbuntuMono, FiraCode)"
[ "$INSTALL_OMZ" = true ] && echo "  ✓ zsh + Oh-My-Zsh"
[ "$INSTALL_STARSHIP" = true ] && echo "  ✓ Starship prompt"
[ "$INSTALL_LIGHTDM" = true ] && echo "  ✓ LightDM Display Manager"
echo ""
echo "Dotfiles configured:"
echo "  ✓ Git configuration (~/.gitconfig)"
echo "  ✓ i3 window manager (~/.config/i3/config)"
echo "  ✓ i3status (~/.config/i3status/config)"
echo "  ✓ Alacritty terminal (~/.config/alacritty/alacritty.toml)"
echo "  ✓ Rofi launcher (~/.config/rofi/config.rasi)"
echo "  ✓ X resources (~/.Xresources)"
[ "$INSTALL_OMZ" = true ] && echo "  ✓ zsh with Oh-My-Zsh and Starship (~/.zshrc)"
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
echo "  Mod+\\           = Lock screen"
echo "  Mod+c           = Clipboard manager"
echo "  Mod+1 to Mod+9  = Switch workspaces"
echo "  Print           = Screenshot"
echo ""
[ "$INSTALL_DOCKER" = true ] && echo "NOTE: For Docker to work without sudo, log out and back in!"
echo ""
echo "Workspace layout:"
echo "  1:term  - Terminal workspace"
echo "  2:rider - Rider IDE workspace"
echo "  3:git   - GitKraken workspace"
echo "  4:web   - Firefox workspace"
echo ""
echo "Enjoy your new Debian i3 development environment! 🚀"
