# Visual Studio / Rider → LazyVim Keybindings

Quick reference for VS/Rider users switching to LazyVim.

## Navigation

| VS/Rider | LazyVim | Action |
|----------|---------|--------|
| `Ctrl+T` | `<space>ss` | Go to Symbol |
| `Ctrl+Shift+T` | `<space>ff` | Go to File |
| `Ctrl+E` | `<space>fr` | Recent Files |
| `Ctrl+G` | `:` then line number | Go to Line |
| `F12` | `gd` | Go to Definition |
| `Ctrl+F12` | `<space>sS` | File Structure (document symbols) |
| `Shift+F12` | `gr` | Find References/Usages |
| `Ctrl+Click` | `gd` | Go to Definition |
| `Alt+Left` | `Ctrl+o` | Navigate Back |
| `Alt+Right` | `Ctrl+i` | Navigate Forward |

## Editing

| VS/Rider | LazyVim | Action |
|----------|---------|--------|
| `Alt+Enter` | `<space>ca` | Code Actions / Quick Fix |
| `F2` | `<space>cr` | Rename Symbol |
| `Ctrl+Space` | `Ctrl+Space` | Trigger Completion |
| `Ctrl+/` | `gcc` | Comment Line |
| (visual) `Ctrl+/` | `gc` | Comment Selection |
| `Ctrl+D` | `yyp` | Duplicate Line |
| `Ctrl+Shift+K` | `dd` | Delete Line |
| `Alt+Up` | `:m .-2<CR>` | Move Line Up |
| `Alt+Down` | `:m .+1<CR>` | Move Line Down |
| `Ctrl+Z` | `u` | Undo |
| `Ctrl+Y` | `Ctrl+r` | Redo |

## Search

| VS/Rider | LazyVim | Action |
|----------|---------|--------|
| `Ctrl+Shift+F` | `<space>sg` | Find in Files (grep) |
| `Ctrl+F` | `/` | Find in File |
| `Ctrl+H` | `:%s/old/new/g` | Replace in File |
| `Ctrl+Shift+A` | `<space>:` | Command Palette |

## Tool Windows

| VS/Rider | LazyVim | Action |
|----------|---------|--------|
| `Ctrl+Alt+L` (Explorer) | `<space>e` | File Explorer |
| Terminal | `<space>ft` | Floating Terminal |
| Error List | `<space>sd` | Diagnostics |
| `Ctrl+Tab` | `H` / `L` | Prev/Next Buffer |
| Close Tab | `<space>bd` | Close Buffer |

## LSP Features

| VS/Rider | LazyVim | Action |
|----------|---------|--------|
| Hover Info | `K` | Show Documentation |
| Go to Definition | `gd` | Definition |
| Go to Implementation | `gI` | Implementation |
| Find References | `gr` | References |
| Rename | `<space>cr` | Rename |
| Code Action | `<space>ca` | Code Actions |
| Format Document | `<space>cf` | Format |
| Next Error | `]d` | Next Diagnostic |
| Prev Error | `[d` | Previous Diagnostic |

## Debugging (requires DAP extra)

| VS/Rider | LazyVim | Action |
|----------|---------|--------|
| `F5` | `<space>dc` | Continue |
| `F9` | `<space>db` | Toggle Breakpoint |
| `F10` | `<space>dO` | Step Over |
| `F11` | `<space>di` | Step Into |
| `Shift+F11` | `<space>do` | Step Out |
| Stop | `<space>dt` | Terminate |

## Buffers & Windows

| VS/Rider | LazyVim | Action |
|----------|---------|--------|
| `Ctrl+Tab` | `<space>fb` | Buffer List |
| Next Tab | `L` or `]b` | Next Buffer |
| Prev Tab | `H` or `[b` | Previous Buffer |
| Close Tab | `<space>bd` | Close Buffer |
| Split Vertical | `<space>|` | Vertical Split |
| Split Horizontal | `<space>-` | Horizontal Split |

## Vim Essentials (learn these!)

| Keys | Action |
|------|--------|
| `i` | Insert mode (before cursor) |
| `a` | Insert mode (after cursor) |
| `o` | New line below, insert mode |
| `O` | New line above, insert mode |
| `Esc` | Normal mode |
| `w` / `b` | Next/previous word |
| `0` / `$` | Start/end of line |
| `gg` / `G` | Start/end of file |
| `ciw` | Change inner word |
| `ci"` | Change inside quotes |
| `dd` | Delete line |
| `yy` | Copy line |
| `p` | Paste |
| `.` | Repeat last action |
| `*` | Search word under cursor |

---

**Note:** `<space>` means press Space (the leader key in LazyVim).
