# Debian 13 Unattended Setup Script

Complete automated setup script for a Debian 13 i3 development environment based on `debian-setup-guide.md` with all dotfiles bundled.

## What's Included

### Software & Tools
- **Window Manager:** i3 + X Server
- **Terminal:** Alacritty with JetBrainsMono Nerd Font
- **Browser:** Firefox ESR
- **File Manager:** Thunar
- **Launcher:** Rofi (with Arc-Dark theme)
- **Development:** .NET 8 SDK, Mono, Docker, EF Core tools, gcc/g++, make, cmake, git
- **Shell:** zsh with Oh-My-Zsh and Starship prompt
- **Fonts:** JetBrainsMono, UbuntuMono, FiraCode Nerd Fonts
- **Audio:** PulseAudio + pavucontrol + system tray control
- **Bluetooth:** Full Bluetooth stack with Blueman GUI
- **Network:** NetworkManager with applet
- **Utilities:** fzf, ripgrep, bat, eza, neovim, tmux, htop, and more
- **Display Manager:** LightDM

### Dotfiles Included
All your personal configurations are bundled:
- `.gitconfig` - Git configuration
- `.config/i3/config` - i3 window manager config with workspace assignments
- `.config/i3status/config` - Clean status bar configuration
- `.config/alacritty/alacritty.toml` - Terminal configuration
- `.config/rofi/config.rasi` - Launcher theme
- `.zshrc` - Oh-My-Zsh + Starship configuration
- `.Xresources` - X server settings (DPI: 144)

## Installation

### Prerequisites
- Fresh Debian 13 installation (no GUI required)
- Internet connection
- SSH access (optional)
- Sudo privileges

### Quick Start

1. **Transfer the script to your Debian system:**
   ```bash
   # Via SCP from another machine:
   scp debian-auto-setup.sh user@debian-host:~

   # Or download if you have it hosted somewhere:
   wget https://your-server.com/debian-auto-setup.sh
   ```

2. **Make it executable:**
   ```bash
   chmod +x debian-auto-setup.sh
   ```

3. **Run the script:**
   ```bash
   ./debian-auto-setup.sh
   ```

4. **Wait 10-20 minutes** (depending on your internet speed)

5. **Reboot:**
   ```bash
   sudo reboot
   ```

6. **Done!** Login via LightDM and i3 will start automatically

## Customization

Edit the configuration variables at the top of the script before running:

```bash
# Git configuration
GIT_USER_NAME="Your Name"
GIT_USER_EMAIL="your.email@example.com"

# Bluetooth device MAC (leave empty to skip)
BLUETOOTH_DEVICE_MAC=""

# Installation toggles
INSTALL_DOTNET_SDK=true           # Install .NET 8 SDK
INSTALL_DOTNET_VERSION="8.0"      # Change to 9.0 or 10.0 if needed
INSTALL_MONO=true                 # .NET Framework compatibility
INSTALL_DOCKER=true               # Docker Engine
INSTALL_EF_TOOLS=true             # Entity Framework CLI tools
INSTALL_OMZ=true                  # Oh-My-Zsh
INSTALL_STARSHIP=true             # Starship prompt
INSTALL_NERD_FONTS=true           # Nerd Fonts
INSTALL_AUDIO=true                # PulseAudio
INSTALL_BLUETOOTH=true            # Bluetooth stack
INSTALL_LIGHTDM=true              # Display manager
INSTALL_OPTIONAL_TOOLS=true       # fzf, ripgrep, bat, eza, etc.

# Fonts to install
NERD_FONTS="JetBrainsMono UbuntuMono FiraCode"
```

## Post-Installation

### i3 Keyboard Shortcuts (Mod = Windows/Super key)

**Basic Navigation:**
- `Mod+Enter` - Open Alacritty terminal
- `Mod+d` - Application launcher (Rofi)
- `Mod+Shift+q` - Close window
- `Mod+Shift+r` - Reload i3 config
- `Mod+Shift+e` - Exit i3

**Workspaces:**
- `Mod+1` to `Mod+9` - Switch to workspace
- `Mod+Shift+1` to `9` - Move window to workspace

**Layout:**
- `Mod+h` - Split horizontally
- `Mod+v` - Split vertically
- `Mod+f` - Fullscreen
- `Mod+s` - Stacking layout
- `Mod+w` - Tabbed layout
- `Mod+e` - Toggle split layout

**Utilities:**
- `Mod+\` - Lock screen
- `Mod+c` - Clipboard manager
- `Print` - Screenshot (saved to ~/Pictures/)
- Volume keys - Adjust volume
- Brightness keys - Adjust brightness

### Workspace Layout

The i3 config includes workspace assignments:
- **1:term** - Terminal workspace
- **2:rider** - Rider IDE (auto-assigned)
- **3:git** - GitKraken (auto-assigned)
- **4:web** - Firefox (auto-assigned)

### Docker Usage

If you installed Docker, you need to **log out and back in** for the docker group to take effect.

Then you can use Docker without sudo:
```bash
docker ps
docker run hello-world
```

### .NET Development

```bash
# Verify .NET installation
dotnet --version

# Create a new console app
dotnet new console -o MyApp
cd MyApp
dotnet run

# Entity Framework commands
dotnet ef migrations add InitialCreate
dotnet ef database update
```

### Oh-My-Zsh & Starship

The script installs both Oh-My-Zsh and Starship prompt. Starship will override the Oh-My-Zsh theme but you still get all the Oh-My-Zsh plugins and features.

**Installed plugins:**
- git - Git aliases and completions
- ssh-agent - Auto-load SSH keys

**Pre-configured aliases:**
- `ll` - `eza -lah` (long list)
- `ls` - `eza` (modern ls replacement)
- `cat` - `bat` (syntax-highlighted cat)
- `gs` - `git status`
- `gp` - `git pull`

## Troubleshooting

### No network after reboot
NetworkManager should be running automatically. If not:
```bash
sudo systemctl start NetworkManager
sudo systemctl enable NetworkManager
```

### i3 doesn't start
Make sure LightDM is running:
```bash
sudo systemctl status lightdm
sudo systemctl start lightdm
```

### Docker permission denied
Log out and back in after installation for docker group to take effect.

### Bluetooth not working
Start bluetooth service:
```bash
sudo systemctl start bluetooth
sudo systemctl enable bluetooth
bluetoothctl
```

### Font not showing icons
Make sure Nerd Fonts are installed:
```bash
fc-list | grep -i "Nerd Font"
```

## Files Created

The script creates/configures these files:
- `~/.gitconfig`
- `~/.zshrc`
- `~/.bashrc` (appends .NET tools path)
- `~/.Xresources`
- `~/.config/i3/config`
- `~/.config/i3status/config`
- `~/.config/alacritty/alacritty.toml`
- `~/.config/rofi/config.rasi`
- `~/.local/share/fonts/` (Nerd Fonts)
- `~/.oh-my-zsh/` (Oh-My-Zsh installation)

## Script Features

- ✅ Fully unattended installation
- ✅ Prompts for sudo password once at start
- ✅ Keeps sudo alive throughout execution
- ✅ Uses non-interactive apt commands
- ✅ Error handling with `set -e`
- ✅ Progress indicators for each step
- ✅ Configurable via variables at top of script
- ✅ Bundles all dotfiles (no external dependencies)

## Based On

This script automates everything in the `debian-setup-guide.md` documentation:
- All package installations
- All system configurations
- All dotfile creations
- All service enablement

## Author

Script created from debian-setup-guide.md
Generated: December 2025
