# Neovim C# IDE Setup Guide

Complete setup guide for configuring Neovim 0.11+ as a full-featured C# IDE on Debian Trixie (testing).

## Prerequisites

- Debian Trixie (testing)
- .NET SDK installed
- Git

## 1. Install Neovim 0.11 from Source

Debian Trixie repos only have 0.10.4, so we need to build from source.

### Install Build Dependencies

```bash
sudo apt install ninja-build gettext cmake unzip curl build-essential \
  libtool libtool-bin autoconf automake pkg-config
```

### Clone and Build Neovim

```bash
# Create source directory if needed
mkdir -p ~/src
cd ~/src

# Clone neovim repository
git clone https://github.com/neovim/neovim.git
cd neovim

# Checkout stable branch (0.11.x)
git checkout stable

# Build
make CMAKE_BUILD_TYPE=RelWithDebInfo

# Install to /usr/local/bin
sudo make install
```

### Verify Installation

```bash
# Check version
nvim --version
# Should show: NVIM v0.11.x

# Check which binary is being used
which nvim
# Should show: /usr/local/bin/nvim
```

### Troubleshooting PATH Issues

If `nvim --version` still shows 0.10.4, you may have the apt version taking precedence:

```bash
# Check if apt version exists
which -a nvim

# Remove apt version (optional)
sudo apt remove neovim

# OR add to ~/.bashrc or ~/.zshrc
export PATH="/usr/local/bin:$PATH"
```

## 2. Install LazyVim

LazyVim is a Neovim distribution with sensible defaults and LSP preconfigured.

### Backup Existing Config (if any)

```bash
# Required
mv ~/.config/nvim{,.bak}

# Optional but recommended
mv ~/.local/share/nvim{,.bak}
mv ~/.local/state/nvim{,.bak}
mv ~/.cache/nvim{,.bak}
```

### Install LazyVim

```bash
git clone https://github.com/LazyVim/starter ~/.config/nvim
rm -rf ~/.config/nvim/.git
```

### First Launch

```bash
nvim
```

LazyVim will automatically install plugins on first launch. Wait for it to complete.

## 3. Install C# Language Support

### Using Mason (Package Manager)

1. Open Mason in Neovim:
   ```
   :Mason
   ```

2. Navigate and install tools:
   - Press `/` to search
   - Type `omnisharp` and press Enter
   - Move cursor to **omnisharp**, press `i` to install
   - Search for `csharpier`, press `i` to install

3. Mason navigation keys:
   - `j/k` or arrow keys - move up/down
   - `/` - search/filter
   - `i` - install tool under cursor
   - `u` - update tool
   - `X` - uninstall tool
   - `g?` - show help
   - `q` - quit

### Verify Installation

In Neovim:
```
:checkhealth mason
```

Or check the installation directory:
```bash
ls ~/.local/share/nvim/mason/packages/
# Should see: omnisharp, csharpier
```

## 4. Test C# IDE Features

### Create Test Project

```bash
mkdir -p ~/test-csharp
cd ~/test-csharp
dotnet new console -n TestApp
cd TestApp
nvim Program.cs
```

### Verify LSP Features

1. **IntelliSense/Completion:**
   - Type `using ` - should get namespace suggestions
   - Type `Console.` - should get method completions

2. **Go to Definition:**
   - Put cursor on `Console`
   - Press `gd` - should jump to definition

3. **Hover Documentation:**
   - Cursor on any type/method
   - Press `K` - should show documentation popup

4. **Diagnostics:**
   - Type invalid code: `int x = "string";`
   - Should see red squiggles/error messages

5. **Code Actions:**
   - On a line with missing `using`
   - Press `<leader>ca` (space-c-a) - should show quick fixes

6. **Check LSP Status:**
   ```
   :LspInfo
   ```
   Should show omnisharp attached to the buffer

## 5. Common LazyVim Keybindings

### File Navigation
- `<leader>ff` - Find files (Telescope)
- `<leader>fg` - Live grep (search in files)
- `<leader>fb` - Browse buffers
- `<leader>e` - Toggle file explorer (neo-tree)

### LSP Features
- `gd` - Go to definition
- `gr` - Find references
- `K` - Hover documentation
- `<leader>ca` - Code actions
- `<leader>rn` - Rename symbol
- `[d` / `]d` - Previous/next diagnostic

### Terminal
- `<leader>ft` - Open floating terminal
- `<leader>fT` - Open terminal in split

### Buffer Management
- `<leader>bd` - Close current buffer
- `<leader>bD` - Close all buffers except current
- `:bufdo bd` - Close all buffers
- `:%bd` - Close all buffers (shorter)
- `:%bd|e#` - Close all but reopen current
- `:qa` - Quit all windows/buffers
- `:qa!` - Quit all, discard unsaved changes

### General
- `<leader>` is Space by default
- `:` - Command mode
- `/` - Search in file
- `<Esc>` or `jk` - Exit insert mode

## 6. File and Folder Management

Use **neo-tree** (file explorer) for file operations:

### Neo-tree Keybindings

Open explorer with `<leader>e`, then:

| Key | Action |
|-----|--------|
| `a` | Add file or directory (end with `/` for folder) |
| `d` | Delete |
| `r` | Rename |
| `c` | Copy |
| `m` | Move |
| `y` | Copy path to clipboard |

### Creating Files and Folders

To add a folder:
1. `<leader>e` - open explorer
2. Navigate to parent directory
3. `a` then type `NewFolder/` (trailing slash makes it a directory)

To add a file in a new folder:
- `a` then type `NewFolder/MyClass.cs` - creates both in one step

Alternative - create from command mode:
```vim
:e src/NewFolder/NewClass.cs
```
Save with `:w` and Neovim will prompt to create the directory.

---

## 7. NuGet Package Management

### Adding Packages

From terminal (`<leader>ft`) or shell out directly:

```bash
dotnet add package StackExchange.Redis
```

Or from nvim command mode:
```vim
:!dotnet add package StackExchange.Redis
```

### Searching for Packages

```bash
dotnet package search Redis
```

After adding packages, OmniSharp should pick them up automatically. If not, run `:LspRestart`.

---

## 8. Solution and Project Management

C# solution/project management is done via `dotnet` CLI:

### Common Commands

```bash
# Add project to solution
dotnet sln add path/to/Project.csproj

# Add project reference
dotnet add reference ../OtherProject/OtherProject.csproj

# Add NuGet package
dotnet add package PackageName

# Remove package
dotnet remove package PackageName

# Create new project
dotnet new classlib -n MyLibrary

# Build solution
dotnet build

# Run project
dotnet run
```

### In Neovim

Use the integrated terminal:
- Press `<leader>ft` to open floating terminal
- Run dotnet commands directly
- Exit terminal: `exit` or `<C-\><C-n>` then `:q`

## 9. Next Steps

### Custom Keybindings (VS/Rider Style)

Copy the Rider keymaps file to your LazyVim config:

```bash
cp ~/repo/Docs/rider-keymaps.lua ~/.config/nvim/lua/config/keymaps.lua
```

This gives you Rider/ReSharper keybindings including:
- `Ctrl+T` - Go to Symbol (Rider's search)
- `Ctrl+Shift+F` - Find in Files
- `Alt+Enter` - Code Actions / Quick Fix
- `F12` / `Ctrl+B` - Go to Definition
- `Shift+F6` / `F2` - Rename
- `Ctrl+Alt+L` - Format Code
- `Alt+1` - File Explorer
- `F5/F9/F10/F11` - Debug controls

See `rider-keymaps.lua` for the full list.

### Enable Auto-formatting on Save

Add to `~/.config/nvim/lua/config/autocmds.lua`:

```lua
-- Format on save
vim.api.nvim_create_autocmd("BufWritePre", {
  pattern = "*.cs",
  callback = function()
    vim.lsp.buf.format({ async = false })
  end,
})
```

### Additional Plugins to Consider

Edit `~/.config/nvim/lua/plugins/custom.lua`:

```lua
return {
  -- Better C# experience
  {
    "Decodetalkers/csharpls-extended-lsp.nvim",
    dependencies = { "nvim-telescope/telescope.nvim" },
  },
  
  -- Optional: debugger support (DAP)
  {
    "mfussenegger/nvim-dap",
  },
}
```

## 10. Updating Neovim

To update to newer versions:

```bash
cd ~/src/neovim
git pull
git checkout stable
make distclean
make CMAKE_BUILD_TYPE=RelWithDebInfo
sudo make install
```

## 11. Troubleshooting

### LSP Not Attaching

```
:LspInfo
:checkhealth
```

Look for errors related to omnisharp or C#.

### Omnisharp Not Found

Check installation:
```bash
find ~/.local/share/nvim/mason -name "*omnisharp*"
```

Reinstall via Mason if needed.

### Completion Not Working

Ensure you're in insert mode and have typed enough characters to trigger completion.
Try manually triggering: `<C-x><C-o>` in insert mode.

### Performance Issues on Large Solutions

Omnisharp can be slow on very large solutions. Consider:
- Close unused buffers
- Disable omnisharp for specific large files if needed
- Use `:LspRestart` to restart the language server

## 12. Additional Resources

- **LazyVim Documentation:** https://www.lazyvim.org/
- **Neovim Documentation:** `:help` in Neovim
- **Mason Packages:** https://github.com/mason-org/mason-registry
- **OmniSharp:** https://github.com/OmniSharp/omnisharp-roslyn
- **Neovim LSP:** `:help lsp`

## WSL Setup (Future)

The same setup works in WSL (Windows Subsystem for Linux):
1. Install WSL with Debian/Ubuntu
2. Follow all steps above
3. Access Windows projects via `/mnt/c/...`
4. Full IDE experience with native .NET SDK integration

---

**Setup Date:** January 2026  
**Neovim Version:** 0.11.x  
**System:** Debian Trixie (testing)
