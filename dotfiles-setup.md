# Dotfiles Setup

Bare git repo method for managing dotfiles across machines.

## The Alias

```bash
alias dotfiles='git --git-dir=$HOME/.dotfiles --work-tree=$HOME'
```

Add this to your `.zshrc` (already included if restoring from this repo).

## Setting Up a New PC

### 1. Set Up SSH Key for GitHub

```bash
# Generate key
ssh-keygen -t ed25519 -C "your_email@example.com"

# Start agent and add key
eval "$(ssh-agent -s)"
ssh-add ~/.ssh/id_ed25519

# Copy public key
cat ~/.ssh/id_ed25519.pub
```

Add the public key at: **GitHub → Settings → SSH and GPG keys → New SSH key**

Test it:
```bash
ssh -T git@github.com
```

### 2. Clone Dotfiles

```bash
# Clone as bare repo
git clone --bare git@github.com:sproko/dotfiles-v2.git $HOME/.dotfiles

# Define alias for this session
alias dotfiles='git --git-dir=$HOME/.dotfiles --work-tree=$HOME'

# Backup existing files that would conflict
mkdir -p ~/.dotfiles-backup
dotfiles checkout 2>&1 | grep -E "^\s+" | awk '{print $1}' | xargs -I{} mv {} ~/.dotfiles-backup/{}

# Checkout files
dotfiles checkout

# Hide untracked files from status
dotfiles config --local status.showUntrackedFiles no
```

### 3. Post-Setup

- Restart shell or `source ~/.zshrc`
- Install packages your configs depend on (nvim, rofi, dunst, i3, etc.)
- Install fonts: `fc-cache -fv` (if fonts are in `~/.local/share/fonts/`)
- Install oh-my-zsh if not tracked

## Daily Usage

```bash
dotfiles status
dotfiles add ~/.config/something
dotfiles commit -m "Add something config"
dotfiles push
```

## Pulling Updates on Another Machine

```bash
dotfiles pull --rebase
```
