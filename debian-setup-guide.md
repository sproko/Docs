# Debian 13 Setup Guide - Minimal i3 Development Environment

## Installation Process

### 1. Creating Bootable USB

**On Windows with Rufus:**
- Select ISO mode (not DD mode)
- Download Debian 13 netinst ISO from https://www.debian.org/

**On Linux/WSL:**
```bash
dd if=debian-13.0.0-amd64-netinst.iso of=/dev/sdX bs=4M status=progress && sync
```

### 2. BIOS/UEFI Settings (for boot issues)
- Disable Secure Boot (if having issues)
- Disable Fast Boot
- Enable USB boot
- UEFI mode is recommended (supports Secure Boot if needed later)

### 3. Booting from USB

**Common boot menu keys:**
- F12, F8, F9, F10, F11, Del, F2, Esc
- Select USB device from boot menu

### 4. Installer Options

**Language/Locale:** Choose your preferred language and region

**Hostname:** Choose a name (e.g., `debian-dev`, `debian-workstation`)

**Domain Name:** Leave blank unless you have a specific domain

**Root Password:** 
- Set a strong password OR
- Leave blank to disable root login (recommended - forces sudo usage)

**User Account:**
- Create your primary user account
- This user will automatically get sudo access if root password was left blank

**Partitioning:**

**Option A - Simple (Guided - Use Entire Disk):**
- Select "Guided - use entire disk"
- Choose your disk
- "All files in one partition" is fine for most uses

**Option B - With LVM (Recommended for snapshots):**
- Select "Guided - use entire disk and set up LVM"
- Enables volume management and snapshots
- Choose your disk
- Confirm partition changes

**Option C - Manual (Advanced):**
- Create partitions as needed
- Typical layout: `/boot` (500MB), `/` (rest), swap (optional)

**Software Selection (CRITICAL - Keep Minimal):**
```
Uncheck ALL desktop environments:
[ ] Debian desktop environment
[ ] GNOME
[ ] Xfce
[ ] GNOME Flashback
[ ] KDE Plasma
[ ] Cinnamon
[ ] MATE
[ ] LXDE
[ ] LXQt

Check only:
[X] SSH server (if you want remote access)
[X] standard system utilities
```

**GRUB Bootloader:**
- Install to primary disk (usually /dev/sda or /dev/nvme0n1)

## Post-Installation Configuration

### 1. First Boot - Essential Setup

**Log in as your regular user** (not root).

#### Configure Sudo (If Root Password Was Set)

If you set a root password during install, your user won't have sudo by default:

```bash
# Switch to root
su -

# Install sudo
apt update
apt install sudo

# Add your user to sudo group
usermod -aG sudo yourusername

# Log out and back in for group changes to take effect
exit
logout
```

Test sudo works:
```bash
sudo apt update
```

### 2. Update System

```bash
# Update package lists
sudo apt update

# Upgrade all packages
sudo apt upgrade -y

# Optional: Install security updates automatically
sudo apt install unattended-upgrades
sudo dpkg-reconfigure -plow unattended-upgrades
```

### 3. Install i3 Window Manager and Core Tools

```bash
# i3 window manager and X server
sudo apt install -y i3 i3status i3lock xorg

# Terminal emulator (choose one or both)
sudo apt install -y alacritty    # Modern, GPU-accelerated
# sudo apt install -y kitty      # Alternative modern terminal

# Application launcher
sudo apt install -y rofi         # Better than dmenu

# File manager (GUI when needed)
sudo apt install -y thunar

# Browser
sudo apt install -y firefox-esr

# Basic utilities
sudo apt install -y vim git curl wget htop tree unzip

# Optional: Better file tools
sudo apt install -y fzf ripgrep fd-find bat eza
```

### 4. Install .NET 8/9/10 SDK

**Good news! As of December 2025, Microsoft has released official Debian 13 packages with libicu76 support.**

**IMPORTANT: Choose SDK for development machines, Runtime for production systems.**

---

#### For Development Machines (Workstations, Test Systems)

**Method 1: Microsoft APT Repository (Recommended)**

```bash
# Remove any broken config from previous attempts
sudo rm -f /etc/apt/sources.list.d/msprod.list
sudo rm -f /etc/apt/sources.list.d/microsoft-prod.list

# Download and install Microsoft's repository configuration
wget https://packages.microsoft.com/config/debian/13/packages-microsoft-prod.deb -O packages-microsoft-prod.deb
sudo dpkg -i packages-microsoft-prod.deb
rm packages-microsoft-prod.deb

# Update package lists
sudo apt update

# Install .NET 8 SDK (LTS - recommended for production applications)
sudo apt install -y dotnet-sdk-8.0

# Or install .NET 9 SDK
sudo apt install -y dotnet-sdk-9.0

# Or install .NET 10 SDK (latest)
sudo apt install -y dotnet-sdk-10.0

# Verify installation
dotnet --version
dotnet --list-sdks
```

**Method 2: Install Script (Alternative method)**

If you prefer a user-local installation or the apt method has issues:

```bash
# Download the installation script
curl -L https://dot.net/v1/dotnet-install.sh -o dotnet-install.sh
chmod +x ./dotnet-install.sh

# Install .NET 8 SDK (LTS - recommended for production)
./dotnet-install.sh --channel 8.0

# Add .NET to PATH - add these lines to ~/.bashrc
echo 'export DOTNET_ROOT=$HOME/.dotnet' >> ~/.bashrc
echo 'export PATH=$PATH:$DOTNET_ROOT:$DOTNET_ROOT/tools' >> ~/.bashrc

# Reload shell config
source ~/.bashrc

# Verify installation
dotnet --version
dotnet --list-sdks
```

---

#### For Production Systems (PVD Controllers, Deployment Machines)

**Install Runtime Only - Much Smaller and Faster**

```bash
# Setup Microsoft repository (if not already done)
wget https://packages.microsoft.com/config/debian/13/packages-microsoft-prod.deb -O packages-microsoft-prod.deb
sudo dpkg -i packages-microsoft-prod.deb
rm packages-microsoft-prod.deb
sudo apt update

# Install ASP.NET Core Runtime (includes .NET Runtime)
# Use this if your apps use ASP.NET Core, web services, or Avalonia UI
sudo apt install -y aspnetcore-runtime-8.0

# OR install just .NET Runtime (smaller, console apps only)
# Use this only if you have simple console applications
sudo apt install -y dotnet-runtime-8.0

# Verify installation
dotnet --list-runtimes
```

**Size Comparison:**
- **SDK (Development):** ~200MB - includes compiler, debugger, build tools
- **ASP.NET Core Runtime (Production):** ~50MB - runs compiled apps, includes web/UI support
- **.NET Runtime (Production - minimal):** ~30MB - runs simple console apps only

**For your 100 PVD systems running Avalonia apps, use `aspnetcore-runtime-8.0`**

---

#### Quick Reference - What to Install Where

| System Type | Package | Why |
|-------------|---------|-----|
| Dev Workstation | `dotnet-sdk-8.0` | Build, compile, debug code |
| Test System | `dotnet-sdk-8.0` | Test and validate before production |
| Production PVD (Avalonia apps) | `aspnetcore-runtime-8.0` | Run compiled apps, 4x smaller than SDK |
| Production (console apps only) | `dotnet-runtime-8.0` | Smallest footprint for simple apps |

### 5. Install Development Tools

```bash
# Build essentials
sudo apt install -y build-essential gcc g++ gdb make cmake

# Version control
sudo apt install -y git git-lfs

# Mono (for .NET Framework 4.8 compatibility during migration)
sudo apt install -y mono-complete

# Verify Mono installation
mono --version

# Optional: Modern development tools
sudo apt install -y neovim       # Modern vim
sudo apt install -y tmux         # Terminal multiplexer
sudo apt install -y direnv       # Directory-specific environments

# Docker (if needed for containerization)
sudo apt install -y docker.io docker-compose
sudo usermod -aG docker $USER    # Add yourself to docker group
```

### 6. Install Nerd Fonts + zsh + Starship (Better Terminal Experience)

**Why Nerd Fonts?**
- Beautiful icons in terminal
- Better coding experience
- Makes Starship prompt look great

**Install Nerd Fonts:**

```bash
# Create fonts directory
mkdir -p ~/.local/share/fonts
cd ~/.local/share/fonts

# Download JetBrains Mono Nerd Font (popular for coding)
wget https://github.com/ryanoasis/nerd-fonts/releases/download/v3.1.1/JetBrainsMono.zip
unzip JetBrainsMono.zip
rm JetBrainsMono.zip

# Download UbuntuMono Nerd Font
wget https://github.com/ryanoasis/nerd-fonts/releases/download/v3.1.1/UbuntuMono.zip
unzip UbuntuMono.zip
rm UbuntuMono.zip

# Optional: Also get FiraCode Nerd Font
wget https://github.com/ryanoasis/nerd-fonts/releases/download/v3.1.1/FiraCode.zip
unzip FiraCode.zip
rm FiraCode.zip

# Rebuild font cache
fc-cache -fv

# Verify fonts installed
fc-list | grep -i "JetBrains"
fc-list | grep -i "Ubuntu"
```

**Install zsh and Starship:**

```bash
# Install zsh shell
sudo apt install -y zsh

# Install Starship prompt
curl -sS https://starship.rs/install.sh | sh

# Change default shell to zsh (requires logout to take effect)
chsh -s /usr/bin/zsh
```

**Configure zsh with Starship:**

```bash
# Create/edit zsh config
nano ~/.zshrc
```

Add this content:
```bash
# Starship prompt
eval "$(starship init zsh)"

# .NET paths (if using script-installed .NET)
export DOTNET_ROOT=$HOME/.dotnet
export PATH=$PATH:$DOTNET_ROOT:$DOTNET_ROOT/tools

# Optional: useful aliases
alias ll='ls -lah'
alias ls='eza'              # Use eza instead of ls (if installed)
alias ll='eza -lah'         # Long format with eza
alias gs='git status'
alias gp='git pull'
```

**Update Alacritty to use Nerd Font:**

Edit `~/.config/alacritty/alacritty.toml`:
```toml
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
```

**Log out and log back in** for zsh to become your default shell.

**Result:** Beautiful terminal with icons, git status, and context-aware prompt! ✨

### 7. Configure i3

**On first launch:**
- i3 will ask to generate a config file - choose **Yes**
- Choose your **Mod key**: 
  - **Mod4 (Windows/Super key)** - Recommended
  - Mod1 (Alt key) - May conflict with applications

**Basic i3 keybindings (with Mod = Super/Windows key):**
```
Mod+Enter          = Open terminal
Mod+d              = Open application launcher (rofi/dmenu)
Mod+Shift+q        = Close focused window
Mod+Shift+e        = Exit i3
Mod+Shift+r        = Reload i3 config
Mod+Shift+c        = Restart i3

Mod+h/j/k/l        = Navigate windows (vim-style)
Mod+arrows         = Navigate windows (arrow keys)

Mod+v              = Split vertically (next window opens below)
Mod+h              = Split horizontally (next window opens to right)

Mod+f              = Toggle fullscreen
Mod+Shift+Space    = Toggle floating mode

Mod+1 to Mod+9     = Switch to workspace 1-9
Mod+Shift+1 to 9   = Move window to workspace 1-9
```

**Customize i3 config:**
```bash
# Edit i3 config
vim ~/.config/i3/config

# Or with nano
nano ~/.config/i3/config
```

**Useful i3 config additions:**

```bash
# Add to ~/.config/i3/config

# Use rofi instead of dmenu
bindsym $mod+d exec --no-startup-id rofi -show drun

# Set wallpaper (install feh first: sudo apt install feh)
exec --no-startup-id feh --bg-scale ~/Pictures/wallpaper.jpg

# Lock screen shortcut
bindsym $mod+l exec --no-startup-id i3lock -c 000000

# Screenshot (install scrot first: sudo apt install scrot)
bindsym Print exec --no-startup-id scrot '%Y-%m-%d_%H-%M-%S.png' -e 'mv $f ~/Pictures/'

# Volume control (install pulseaudio-utils: sudo apt install pulseaudio-utils)
bindsym XF86AudioRaiseVolume exec --no-startup-id pactl set-sink-volume @DEFAULT_SINK@ +5%
bindsym XF86AudioLowerVolume exec --no-startup-id pactl set-sink-volume @DEFAULT_SINK@ -5%
bindsym XF86AudioMute exec --no-startup-id pactl set-sink-mute @DEFAULT_SINK@ toggle

# Brightness control (install brightnessctl: sudo apt install brightnessctl)
bindsym XF86MonBrightnessUp exec --no-startup-id brightnessctl set +10%
bindsym XF86MonBrightnessDown exec --no-startup-id brightnessctl set 10%-
```

After editing config:
```
Mod+Shift+r to reload i3
```

### 8. Audio Setup

**Install PulseAudio and controls:**

```bash
# Install audio stack
sudo apt install -y pulseaudio pavucontrol alsa-utils

# Install system tray volume control
sudo apt install -y pasystray

# Start PulseAudio
pulseaudio --start

# Test audio
speaker-test -c 2 -t wav
# Press Ctrl+C to stop when you hear sound
```

**Add to i3 config** (`~/.config/i3/config`):

```bash
# Volume controls
bindsym XF86AudioRaiseVolume exec --no-startup-id pactl set-sink-volume @DEFAULT_SINK@ +5%
bindsym XF86AudioLowerVolume exec --no-startup-id pactl set-sink-volume @DEFAULT_SINK@ -5%
bindsym XF86AudioMute exec --no-startup-id pactl set-sink-mute @DEFAULT_SINK@ toggle

# Start volume tray icon
exec --no-startup-id pasystray
```

**Enable system tray in i3bar** - find or add the `bar` section:

```bash
bar {
    status_command i3status
    position top
    tray_output primary
    tray_padding 2
    
    colors {
        background #000000
        statusline #ffffff
        separator #666666
    }
}
```

**Control volume:**
- Volume keys on keyboard
- Click speaker icon in system tray
- Run `pavucontrol` for full mixer GUI

### 9. Bluetooth Setup (Keyboards, Mice, Headphones)

**Install Bluetooth stack:**

```bash
# Install Bluetooth packages
sudo apt install -y bluetooth bluez bluez-tools pulseaudio-module-bluetooth

# Install firmware (needed for many USB Bluetooth dongles)
sudo apt install -y firmware-realtek firmware-atheros firmware-iwlwifi

# Start and enable Bluetooth service
sudo systemctl start bluetooth
sudo systemctl enable bluetooth

# Check Bluetooth is running
sudo systemctl status bluetooth
```

**Check if Bluetooth hardware is detected:**

```bash
# Check for USB Bluetooth dongles
lsusb | grep -i bluetooth

# Check for built-in Bluetooth
lspci | grep -i bluetooth

# Check Bluetooth controller is available
bluetoothctl list

# Should show something like:
# Controller XX:XX:XX:XX:XX:XX YourHostname [default]
```

**If no controller appears:**

```bash
# Load Bluetooth kernel module
sudo modprobe btusb

# Bring up Bluetooth interface
sudo hciconfig hci0 up

# Restart Bluetooth service
sudo systemctl restart bluetooth

# Check again
bluetoothctl list
```

**Pair a Bluetooth device (keyboard, mouse, headphones):**

```bash
# Start bluetoothctl
bluetoothctl

# Inside bluetoothctl, run these commands:
power on
agent on
default-agent
scan on

# Turn on your Bluetooth device and put it in pairing mode
# Watch for your device to appear:
# [NEW] Device XX:XX:XX:XX:XX:XX DeviceName

# When you see it, use the MAC address shown:
pair XX:XX:XX:XX:XX:XX

# For keyboards: You may be prompted to enter a PIN
# Type the PIN on the keyboard and press Enter

# After pairing succeeds:
trust XX:XX:XX:XX:XX:XX     # Auto-connect in future
connect XX:XX:XX:XX:XX:XX   # Connect now

# Stop scanning
scan off

# Exit
exit
```

**For Bluetooth audio devices (headphones, speakers):**

After pairing and connecting, set audio output:

```bash
# Open PulseAudio volume control
pavucontrol
```

In pavucontrol:
1. **Configuration** tab → Set Bluetooth device profile to **"A2DP Sink"** (high quality)
2. **Output Devices** tab → Set Bluetooth device as default (green checkmark)

Or use command line:
```bash
# List audio sinks
pactl list short sinks

# Set Bluetooth device as default
pactl set-default-sink bluez_sink.XX_XX_XX_XX_XX_XX.a2dp_sink
```

**Auto-connect Bluetooth devices on startup:**

Add to `~/.config/i3/config`:
```bash
# Auto-connect Bluetooth keyboard (replace with your device MAC)
exec --no-startup-id bluetoothctl connect XX:XX:XX:XX:XX:XX
```

**Bluetooth System Tray Applet (Recommended):**

For easy GUI management of Bluetooth devices:

```bash
# Install Blueman (Bluetooth manager with system tray applet)
sudo apt install -y blueman
```

Add to `~/.config/i3/config`:
```bash
# Start Blueman applet in system tray
exec --no-startup-id blueman-applet
```

**Reload i3:** `Mod+Shift+R`

You'll see a Bluetooth icon in your system tray. Click it to:
- See paired devices
- Connect/disconnect devices quickly
- Pair new devices with GUI
- View device battery levels

**Useful Bluetooth commands:**

```bash
# List paired devices
bluetoothctl devices

# Show device info
bluetoothctl info XX:XX:XX:XX:XX:XX

# Connect to a known device
bluetoothctl connect XX:XX:XX:XX:XX:XX

# Disconnect
bluetoothctl disconnect XX:XX:XX:XX:XX:XX

# Remove (unpair) device
bluetoothctl remove XX:XX:XX:XX:XX:XX
```

### 10. Terminal Font Configuration (Alacritty)

**Switch i3 to use Alacritty:**

Edit `~/.config/i3/config` and change:
```bash
# From:
bindsym $mod+Return exec i3-sensible-terminal

# To:
bindsym $mod+Return exec alacritty
```

**Configure Alacritty font size:**

```bash
# Create config directory
mkdir -p ~/.config/alacritty

# Edit config
nano ~/.config/alacritty/alacritty.toml
```

Add:
```toml
[font]
size = 14.0

[font.normal]
family = "monospace"
style = "Regular"

[colors.primary]
background = "#1e1e1e"
foreground = "#d4d4d4"

[window]
padding.x = 10
padding.y = 10
```

**Reload i3:** `Mod+Shift+R`

**Adjust font on the fly in Alacritty:**
- `Ctrl + +` = Increase
- `Ctrl + -` = Decrease
- `Ctrl + 0` = Reset

### 11. Workspace Management & Auto-Launch Apps

**Set up workspace assignments** - add to `~/.config/i3/config`:

```bash
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

# Workspace assignments (apps auto-move to these workspaces)
assign [class="jetbrains-rider"] 2
assign [class="Rider"] 2
assign [class="GitKraken"] 3
assign [class="firefox"] 4
assign [class="Firefox"] 4

# Auto-start applications on i3 startup
exec --no-startup-id i3-msg 'workspace 1; exec alacritty'
exec --no-startup-id i3-msg 'workspace 2; exec rider'
exec --no-startup-id i3-msg 'workspace 3; exec gitkraken'
exec --no-startup-id i3-msg 'workspace 4; exec firefox'

# Switch to workspace
bindsym $mod+1 workspace $ws1
bindsym $mod+2 workspace $ws2
bindsym $mod+3 workspace $ws3
bindsym $mod+4 workspace $ws4
bindsym $mod+5 workspace $ws5
bindsym $mod+6 workspace $ws6
bindsym $mod+7 workspace $ws7
bindsym $mod+8 workspace $ws8
bindsym $mod+9 workspace $ws9
bindsym $mod+0 workspace $ws10

# Move focused container to workspace
bindsym $mod+Shift+1 move container to workspace $ws1
bindsym $mod+Shift+2 move container to workspace $ws2
bindsym $mod+Shift+3 move container to workspace $ws3
bindsym $mod+Shift+4 move container to workspace $ws4
bindsym $mod+Shift+5 move container to workspace $ws5
bindsym $mod+Shift+6 move container to workspace $ws6
bindsym $mod+Shift+7 move container to workspace $ws7
bindsym $mod+Shift+8 move container to workspace $ws8
bindsym $mod+Shift+9 move container to workspace $ws9
bindsym $mod+Shift+0 move container to workspace $ws10
```

**Find correct window class names** (if apps don't assign properly):

```bash
# Run this, then click the application window
xprop | grep WM_CLASS

# Use the second name in the assign rule
# Example output: WM_CLASS(STRING) = "gitkraken", "GitKraken"
# Use: assign [class="GitKraken"] 3
```

**Result:** On i3 startup, your workspace layout is ready:
- Workspace 1: Terminal
- Workspace 2: Rider IDE
- Workspace 3: GitKraken
- Workspace 4: Firefox

Press `Mod+1` through `Mod+4` to switch between them instantly!

### 12. Clipboard Manager (Copy/Paste Between Apps)

**Install diodon clipboard manager:**

```bash
# Install diodon
sudo apt install -y diodon

# Optional: Install autocutsel for better clipboard sync
sudo apt install -y autocutsel
```

**Add to i3 config** (`~/.config/i3/config`):

```bash
# Clipboard manager
exec --no-startup-id diodon

# Keyboard shortcut to access clipboard history
bindsym $mod+c exec --no-startup-id diodon

# Optional: Sync X11 clipboard selections for better compatibility
exec --no-startup-id autocutsel -fork
exec --no-startup-id autocutsel -selection PRIMARY -fork
```

**Reload i3:** `Mod+Shift+R`

**Usage:**
- **Copy in terminal:** Select text with mouse (automatically copied)
- **Copy in apps:** `Ctrl+C` (standard)
- **Paste in terminal:** `Shift+Insert` or middle mouse button
- **Paste in apps:** `Ctrl+V` (standard)
- **Clipboard history:** `Mod+C` - shows all recent clipboard items

**diodon also appears in system tray** - click the icon to access clipboard history.

### 13. Clean Up i3 Status Bar

By default, i3status shows a lot of unnecessary info (WiFi, battery, IPv6). Let's clean it up for a desktop/workstation setup.

**Create a custom i3status config:**

```bash
# Create config directory
mkdir -p ~/.config/i3status

# Create config file
nano ~/.config/i3status/config
```

**Add this clean configuration:**

```
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
```

**Reload i3:** `Mod+Shift+R`

**What this config shows:**
- CPU usage percentage
- Available disk space
- RAM usage (used/total)
- Ethernet IP address and link speed
- Date and time

**What it removes:**
- ❌ WiFi status (not needed on desktop)
- ❌ Battery status (not needed on desktop)
- ❌ IPv6 address (usually not needed)
- ❌ System load average (redundant with CPU usage)

**Your system tray still shows:**
- 🔵 Blueman (Bluetooth)
- 📋 Diodon (Clipboard)
- 🌐 Network Manager icon
- 🔊 Volume control

Clean status bar + functional tray = perfect balance!

### 14. Display Manager for i3 Login

**Install LightDM (Recommended):**

LightDM provides a graphical login screen and automatically starts i3 when you log in.

```bash
# Install LightDM
sudo apt install -y lightdm

# It will start automatically on boot
# You'll get a graphical login screen
```

**Using LightDM:**
1. Reboot your system
2. You'll see a graphical login screen
3. Enter your username and password
4. i3 will be selected by default (or select it from the session menu)
5. Login and i3 starts automatically!

**Alternative - Auto-start X on console login:**

If you prefer no display manager (direct console login):

Add to `~/.bash_profile` or `~/.zprofile` (if using zsh):
```bash
# Start X on login to tty1
if [ -z "$DISPLAY" ] && [ "$XDG_VTNR" = 1 ]; then
  exec startx
fi
```

Log out and back in - i3 will start automatically.

**Note:** Most users prefer LightDM for the cleaner experience and easier session management.

### 8. Network Configuration

Network should work automatically with DHCP via NetworkManager or systemd-networkd.

**Check network status:**
```bash
# Show network interfaces
ip addr

# Show active connections
ip link

# Test connectivity
ping -c 3 debian.org
```

**Optional - Install NetworkManager for easier wifi management:**
```bash
sudo apt install -y network-manager network-manager-gnome

# Enable NetworkManager
sudo systemctl enable NetworkManager
sudo systemctl start NetworkManager

# GUI tool for managing networks
nm-applet &  # Run in i3 startup
```

**Add to i3 config for network manager applet:**
```bash
# Add to ~/.config/i3/config
exec --no-startup-id nm-applet
```

### 9. SSH Configuration

If you installed SSH server during installation:

```bash
# Check SSH status
sudo systemctl status ssh

# Start SSH
sudo systemctl start ssh

# Enable on boot
sudo systemctl enable ssh

# Check SSH is listening
sudo ss -tulpn | grep :22
```

**Connect from another machine:**
```bash
ssh yourusername@debian-dev
# or
ssh yourusername@192.168.1.xxx
```

### 10. Hostname Resolution for Network Access

**Option A - Router DNS (easiest):**
Most routers register DHCP hostnames. Try:
```bash
ssh username@debian-dev
```

**Option B - Edit hosts file on other machines:**

On Windows: Edit `C:\Windows\System32\drivers\etc\hosts` as Administrator
On Linux/Mac: Edit `/etc/hosts` with sudo

Add:
```
192.168.1.xxx    debian-dev
```

**Option C - Avahi/mDNS (Bonjour-like):**
```bash
sudo apt install -y avahi-daemon
sudo systemctl enable avahi-daemon
sudo systemctl start avahi-daemon
```

Access as `debian-dev.local` from other machines.

## Testing Your Setup

### Test .NET Development
```bash
# Verify .NET
dotnet --version

# Create test console app
mkdir ~/testapp
cd ~/testapp
dotnet new console
dotnet run

# Create test Avalonia app (if doing GUI development)
dotnet new install Avalonia.Templates
dotnet new avalonia.app -o MyAvaloniaApp
cd MyAvaloniaApp
dotnet run
```

### Test C/C++ Development
```bash
# Check compiler
gcc --version
g++ --version

# Create test program
cat > test.cpp << 'EOF'
#include <iostream>
int main() {
    std::cout << "Hello Debian!" << std::endl;
    return 0;
}
EOF

# Compile and run
g++ -o test test.cpp
./test

# Compile with debug symbols
g++ -g -o test test.cpp

# Debug with GDB
gdb ./test
# (gdb) break main
# (gdb) run
# (gdb) continue
# (gdb) quit
```

### Test i3 Setup
```
# In i3:
Mod+Enter              # Should open terminal (alacritty)
Mod+d                  # Should open rofi launcher
Mod+Shift+r            # Should reload i3 config
```

### Check System Resources
```bash
# Disk usage
df -h

# Memory usage
free -h

# Running processes
htop

# System info
neofetch    # Install: sudo apt install neofetch
```

## Quick Reference Commands

### Service Management (systemd)
```bash
# Start a service
sudo systemctl start servicename

# Stop a service
sudo systemctl stop servicename

# Restart a service
sudo systemctl restart servicename

# Check service status
sudo systemctl status servicename

# Enable service at boot
sudo systemctl enable servicename

# Disable service at boot
sudo systemctl disable servicename

# View service logs
sudo journalctl -u servicename
```

### Package Management (APT)
```bash
# Update package lists
sudo apt update

# Upgrade all packages
sudo apt upgrade

# Install a package
sudo apt install packagename

# Remove a package
sudo apt remove packagename

# Remove package and config files
sudo apt purge packagename

# Search for packages
apt search searchterm

# Show package info
apt show packagename

# List installed packages
apt list --installed

# Clean up unused packages
sudo apt autoremove

# Clean package cache
sudo apt clean
```

### Network Commands
```bash
# Show network interfaces
ip addr
ip link

# Show routing table
ip route

# Test connectivity
ping -c 3 debian.org

# DNS lookup
nslookup debian.org
dig debian.org

# Show listening ports
sudo ss -tulpn

# Network connections
ss -tupn
```

### System Information
```bash
# Debian version
cat /etc/debian_version
lsb_release -a

# Kernel version
uname -a

# CPU information
lscpu

# Memory information
free -h

# Disk information
lsblk
df -h

# PCI devices
lspci

# USB devices
lsusb

# System logs
journalctl -xe
dmesg | less
```

### File System Management
```bash
# Disk usage by directory
du -sh */

# Find large files
find / -type f -size +100M 2>/dev/null

# LVM snapshot (if using LVM)
sudo lvcreate -L 1G -s -n root-snapshot /dev/mapper/vgname-root

# List snapshots
sudo lvs

# Remove snapshot
sudo lvremove /dev/mapper/vgname-root--snapshot
```

## Automation Script (Basic Setup)

Save as `setup-debian-i3.sh`:

```bash
#!/bin/bash
# Debian 13 i3 Development Environment Setup
# Run as regular user (will prompt for sudo password)

set -e

echo "=== Debian i3 Development Setup ==="
echo

# Update system
echo "Updating system..."
sudo apt update
sudo apt upgrade -y

# Install i3 and X
echo "Installing i3 window manager..."
sudo apt install -y i3 i3status i3lock xorg rofi

# Install terminal and utilities
echo "Installing terminal and utilities..."
sudo apt install -y alacritty thunar firefox-esr
sudo apt install -y vim git curl wget htop tree fzf ripgrep

# Install .NET
echo "Installing .NET 8 SDK..."
sudo apt install -y dotnet-sdk-8.0

# Install development tools
echo "Installing development tools..."
sudo apt install -y build-essential gcc g++ gdb make cmake
sudo apt install -y neovim tmux

# Optional: Docker
read -p "Install Docker? (y/n) " -n 1 -r
echo
if [[ $REPLY =~ ^[Yy]$ ]]; then
    echo "Installing Docker..."
    sudo apt install -y docker.io docker-compose
    sudo usermod -aG docker $USER
    echo "Log out and back in for Docker group to take effect"
fi

# Create basic i3 config if it doesn't exist
if [ ! -f ~/.config/i3/config ]; then
    echo "Creating i3 config directory..."
    mkdir -p ~/.config/i3
fi

echo
echo "=== Setup Complete ==="
echo
echo "To start i3, run: startx"
echo "Or reboot and login to start i3 automatically"
echo
echo "Basic i3 shortcuts:"
echo "  Mod+Enter       = Terminal"
echo "  Mod+d           = Application launcher"
echo "  Mod+Shift+q     = Close window"
echo "  Mod+Shift+e     = Exit i3"
echo
echo "Enjoy your minimal Debian i3 setup!"
```

Make executable and run:
```bash
chmod +x setup-debian-i3.sh
./setup-debian-i3.sh
```

## Common Issues and Solutions

### No Network After Install
```bash
# Check interface name
ip link

# Bring interface up
sudo ip link set dev eth0 up

# Request DHCP
sudo dhclient eth0

# Make permanent - install NetworkManager
sudo apt install network-manager
sudo systemctl enable NetworkManager
sudo systemctl start NetworkManager
```

### Can't Start X / i3 Won't Launch
```bash
# Install missing X server
sudo apt install xorg

# Check for errors
cat ~/.local/share/xorg/Xorg.0.log

# Try with different video driver
sudo apt install xserver-xorg-video-intel  # Intel
sudo apt install xserver-xorg-video-amd    # AMD
sudo apt install xserver-xorg-video-nouveau # NVIDIA (open)
```

### SSH Connection Refused
```bash
# Install SSH server if missing
sudo apt install openssh-server

# Start SSH
sudo systemctl start ssh
sudo systemctl enable ssh

# Check firewall (if enabled)
sudo ufw status
sudo ufw allow 22
```

### Sudo Not Working
```bash
# Switch to root
su -

# Add user to sudo group
usermod -aG sudo yourusername

# Log out and back in
exit
logout
```

### .NET Installation / Runtime Issues

**libicu dependency error when installing via apt:**
```bash
# Error: "depends on libicu74 | libicu72... but libicu76 is installed"
# Solution: Use the install script method instead (see Install .NET section)

curl -L https://dot.net/v1/dotnet-install.sh -o dotnet-install.sh
chmod +x ./dotnet-install.sh
./dotnet-install.sh --channel 8.0

# Add to PATH
export DOTNET_ROOT=$HOME/.dotnet
export PATH=$PATH:$DOTNET_ROOT:$DOTNET_ROOT/tools
```

**"Could not load ICU data" error when running .NET:**
```bash
# Check which libicu version is installed
apt-cache search libicu

# Temporary workaround (disables globalization - may break some apps)
export DOTNET_SYSTEM_GLOBALIZATION_INVARIANT=1

# Better solution: Use script-installed .NET or wait for Microsoft package updates
```

**dotnet command not found after script install:**
```bash
# Add to ~/.bashrc permanently
echo 'export DOTNET_ROOT=$HOME/.dotnet' >> ~/.bashrc
echo 'export PATH=$PATH:$DOTNET_ROOT:$DOTNET_ROOT/tools' >> ~/.bashrc

# Reload shell
source ~/.bashrc

# Verify
dotnet --version
```

### LVM Snapshots (If Using LVM)
```bash
# Create snapshot
sudo lvcreate -L 5G -s -n root-backup /dev/vgname/root

# List logical volumes
sudo lvs

# Restore from snapshot (BE CAREFUL!)
# Boot from live USB first, then:
sudo lvconvert --merge /dev/vgname/root-backup

# Remove snapshot
sudo lvremove /dev/vgname/root-backup
```

## Next Steps for Learning & Customization

### 1. Customize i3
- Edit `~/.config/i3/config`
- Change colors, keybindings, workspace names
- Add status bar customizations
- Browse r/unixporn for inspiration

### 2. Set Up Development Environment
```bash
# Install your preferred editor config
# Neovim with modern config
git clone https://github.com/NvChad/NvChad ~/.config/nvim --depth 1

# Or VS Code
sudo snap install code --classic  # If you don't mind Snap
# Or download .deb from code.visualstudio.com

# Set up .NET development
dotnet new install Avalonia.Templates
```

### 3. Explore Debian Package System
```bash
# Browse available packages
apt search keyword

# Show package dependencies
apt-cache depends packagename

# Show what depends on a package
apt-cache rdepends packagename

# List files in a package
dpkg -L packagename
```

### 4. System Monitoring & Performance
```bash
# Install monitoring tools
sudo apt install htop iotop nethogs

# System resource monitor
htop

# Disk I/O monitor
sudo iotop

# Network bandwidth monitor
sudo nethogs
```

### 5. Backup Strategy
```bash
# If using LVM - create regular snapshots
sudo lvcreate -L 5G -s -n root-$(date +%Y%m%d) /dev/vgname/root

# Simple home directory backup
rsync -av --delete ~/important-stuff/ /backup/location/

# Full system backup with rsync
sudo rsync -aAXv --exclude={"/dev/*","/proc/*","/sys/*","/tmp/*","/run/*","/mnt/*","/media/*","/lost+found"} / /backup/location/
```

## Recommended Additional Packages

### For Industrial Control Development
```bash
# Serial port tools
sudo apt install minicom screen

# Network debugging
sudo apt install wireshark tcpdump nmap

# Industrial protocols (if available)
# Check for EtherNet/IP, Modbus, etc. libraries
```

### Production Deployment Strategy (For 100+ Systems)

**For deploying to your PVD control systems:**

**1. Create a Base Image / Golden Master:**
```bash
# On a test system, install minimal Debian + runtime
sudo apt install -y aspnetcore-runtime-8.0

# Install only required packages
# No desktop environment, no development tools
# Just what's needed to run your apps

# Test thoroughly with your actual PVD applications
# Verify PLC communication, stepper controllers, etc.

# Create snapshot or image for deployment
```

**2. Automated Deployment Script:**
```bash
#!/bin/bash
# deploy-production.sh - Run on each PVD system

# Update system
apt update && apt upgrade -y

# Install .NET Runtime (not SDK!)
wget https://packages.microsoft.com/config/debian/13/packages-microsoft-prod.deb
dpkg -i packages-microsoft-prod.deb
apt update
apt install -y aspnetcore-runtime-8.0

# Deploy your application
# (Copy from network share, extract tarball, etc.)

# Set up systemd service for your app
# Configure autostart, monitoring, etc.
```

**3. Package Size Considerations:**
- Runtime-only deployment: ~50MB per system
- Full SDK deployment: ~200MB per system  
- **Savings: 150MB × 100 systems = 15GB saved**
- Faster deployment, less disk usage

**4. Update Strategy:**
```bash
# Security updates only (stable, predictable)
sudo apt update
sudo apt upgrade -y aspnetcore-runtime-8.0

# Or pin to specific version for consistency across all systems
sudo apt-mark hold aspnetcore-runtime-8.0
```

**5. Recommended Production Setup:**
- Base OS: Debian 13 minimal (no GUI)
- Runtime: `aspnetcore-runtime-8.0`
- Your Avalonia app: Self-contained or framework-dependent
- Monitoring: systemd service with auto-restart
- Updates: Controlled, tested on dev/staging first

### For Better Terminal Experience
```bash
# Modern shell
sudo apt install zsh
sh -c "$(curl -fsSL https://raw.githubusercontent.com/ohmyzsh/ohmyzsh/master/tools/install.sh)"

# Better prompt
sudo apt install starship
echo 'eval "$(starship init bash)"' >> ~/.bashrc

# Better ls (exa)
sudo apt install exa
alias ls='exa'
```

### For Multimedia
```bash
# Image viewer
sudo apt install feh sxiv

# Video player
sudo apt install mpv

# Audio
sudo apt install pavucontrol  # PulseAudio volume control
```

## Resources

- Debian Documentation: https://www.debian.org/doc/
- i3 User Guide: https://i3wm.org/docs/userguide.html
- Debian Wiki: https://wiki.debian.org/
- .NET on Linux: https://learn.microsoft.com/en-us/dotnet/core/install/linux-debian
- Arch Wiki (often applicable): https://wiki.archlinux.org/

## Key Differences from FreeBSD

| Feature | FreeBSD | Debian |
|---------|---------|--------|
| Init System | rc.d | systemd |
| Package Manager | pkg | apt |
| Config Location | /etc/rc.conf | /etc/systemd/ or service-specific |
| Kernel | Single BSD kernel | Linux kernel + modules |
| Filesystem | ZFS native | ext4/LVM default, ZFS available |
| Containers | Jails | Docker/LXC |
| Network Config | /etc/rc.conf | NetworkManager or /etc/network/interfaces |

---

**Document Version:** 1.0  
**Debian Version:** 13.x "Trixie"  
**Last Updated:** December 2025  
**Target Use:** Minimal i3 development environment for .NET/C# industrial control systems
# Docker Engine Setup for Debian

## Installation
```bash
# Update package index
sudo apt update

# Install Docker Engine and Docker Compose
sudo apt install docker.io docker-compose-v2

# Start and enable Docker service
sudo systemctl start docker
sudo systemctl enable docker
```

## User Permissions
```bash
# Add your user to docker group (required for non-root access)
sudo usermod -aG docker $USER

# NOTE: You must log out and back in for group membership to take effect
# Or activate immediately in current shell:
newgrp docker
```

## Verify Installation
```bash
# Check Docker service status
sudo systemctl status docker

# Test Docker works
docker ps

# Run hello-world test container
docker run hello-world
```

## Rider Configuration

1. Open Rider
2. **File → Settings → Build, Execution, Deployment → Docker**
3. Click **+** to add a new Docker connection
4. Select **Unix socket**
5. Path: `/var/run/docker.sock`
6. Click **Test Connection** - should show "Connection successful"
7. Click **Apply** and **OK**

## Troubleshooting

### Permission denied on /var/run/docker.sock
- Ensure you added yourself to docker group (see User Permissions above)
- Log out and log back in
- Verify with: `groups` (should see 'docker' in the list)

### KVM/Virtualization errors
- Docker Engine does NOT require KVM or virtualization on Linux
- If you see KVM errors, you likely have Docker Desktop installed (not needed on Linux)
- Remove Docker Desktop and use Docker Engine instead

## Notes

- Docker Engine is native on Linux and does not require virtualization
- Docker Desktop is unnecessary on Linux for most development workflows
- Docker Engine is lighter and faster than Docker Desktop on Linux
# .NET EF Core Tools Setup for Debian

## Installation
```bash
# Install EF Core CLI tools globally
dotnet tool install --global dotnet-ef

# Verify installation
dotnet ef --version
```

## Updating EF Tools
```bash
# Update to latest version
dotnet tool update --global dotnet-ef
```

## PATH Configuration

If `dotnet ef` command is not found after installation, add .NET tools to your PATH:
```bash
# Add to ~/.bashrc or ~/.zshrc
export PATH="$PATH:$HOME/.dotnet/tools"

# Reload shell configuration
source ~/.bashrc
# or
source ~/.zshrc
```

## Common Commands
```bash
# Create a migration
dotnet ef migrations add MigrationName

# Update database
dotnet ef database update

# Remove last migration
dotnet ef migrations remove

# List migrations
dotnet ef migrations list

# Generate SQL script
dotnet ef migrations script
```

## Project Requirements

Your project needs the following package for EF tools to work:
```bash
dotnet add package Microsoft.EntityFrameworkCore.Design
```

## Troubleshooting

### Command not found
- Ensure tools are installed: `dotnet tool list --global`
- Check PATH includes `~/.dotnet/tools`
- Restart terminal after adding to PATH

### Tools version mismatch
- EF tools version should match your EF Core package version
- Example: EF Core 9.0.x → dotnet-ef 9.0.x
- Update tools: `dotnet tool update --global dotnet-ef`

## Notes

- EF tools are installed per-user, not system-wide
- Tools are stored in `~/.dotnet/tools`
- Always run `dotnet ef` commands from your project directory
