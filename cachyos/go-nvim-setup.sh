#!/bin/bash
# Go development setup for LazyVim on CachyOS
# Installs Go, enables LazyVim's lang.go extra, lets gopls see `//go:build integration`
# files, and pre-installs the Mason tools so the first nvim launch doesn't stall.
# Safe to re-run: every step checks before it changes anything.
#
# Make executable before running:
#   chmod +x go-nvim-setup.sh
#   ./go-nvim-setup.sh

set -e  # Exit on error

NVIM_DIR="$HOME/.config/nvim"
LAZYVIM_JSON="$NVIM_DIR/lazyvim.json"
GO_PLUGIN="$NVIM_DIR/lua/plugins/go.lua"
GO_EXTRA="lazyvim.plugins.extras.lang.go"
MASON_TOOLS="gopls goimports gofumpt delve"
MASON_BIN="$HOME/.local/share/nvim/mason/bin"

# ============================================================================
# STEP 1: Go toolchain
# ============================================================================
echo "==> Go toolchain"
if command -v go >/dev/null 2>&1; then
    echo "    already installed: $(go version)"
else
    sudo pacman -S --needed --noconfirm go
    echo "    installed: $(go version)"
fi

if [ ! -f "$LAZYVIM_JSON" ]; then
    echo "!!  $LAZYVIM_JSON not found - install LazyVim first, then re-run."
    exit 1
fi

# ============================================================================
# STEP 2: LazyVim lang.go extra (gopls, goimports/gofumpt on save, delve, treesitter)
# ============================================================================
echo "==> LazyVim extra: lang.go"
if grep -q "\"$GO_EXTRA\"" "$LAZYVIM_JSON"; then
    echo "    already enabled"
elif grep -q '"extras": \[\]' "$LAZYVIM_JSON"; then
    sed -i "s|\"extras\": \[\]|\"extras\": [\"$GO_EXTRA\"]|" "$LAZYVIM_JSON"
    echo "    enabled"
else
    # LazyVim re-sorts this list itself on its next write, so position doesn't matter.
    sed -i "/\"extras\": \[/a\\    \"$GO_EXTRA\"," "$LAZYVIM_JSON"
    echo "    enabled"
fi

# ============================================================================
# STEP 3: gopls build tags
# ============================================================================
# gopls skips files behind `//go:build integration` by default, so integration tests
# and their shared helpers show as unresolved. Harmless for projects without the tag.
echo "==> gopls build tags ($GO_PLUGIN)"
if [ -f "$GO_PLUGIN" ]; then
    echo "    already exists - left untouched"
else
    mkdir -p "$(dirname "$GO_PLUGIN")"
    cat > "$GO_PLUGIN" <<'EOF'
return {
  -- Analyze files behind `//go:build integration` too (e.g. Postgres integration tests
  -- and their shared helpers); gopls skips tagged files by default, leaving them unresolved.
  {
    "neovim/nvim-lspconfig",
    opts = {
      servers = {
        gopls = {
          settings = {
            gopls = { buildFlags = { "-tags=integration" } },
          },
        },
      },
    },
  },
}
EOF
    echo "    written"
fi

# ============================================================================
# STEP 4: Plugins and Mason tools
# ============================================================================
# Mason is lazy-loaded, so :MasonInstall only exists after loading it explicitly.
echo "==> Syncing plugins (headless)"
(cd /tmp && nvim --headless "+Lazy! sync" +qa >/dev/null 2>&1) || echo "    Lazy sync reported errors - check :Lazy in nvim"

echo "==> Installing Mason tools: $MASON_TOOLS"
(cd /tmp && nvim --headless -c "Lazy! load mason.nvim" -c "MasonInstall $MASON_TOOLS" -c qa >/dev/null 2>&1) \
    || echo "    MasonInstall reported errors - check :Mason in nvim"

# ============================================================================
# VERIFY
# ============================================================================
echo "==> Verify"
missing=0
for bin in gopls goimports gofumpt dlv; do
    if [ -x "$MASON_BIN/$bin" ]; then
        echo "    ok       $bin"
    else
        echo "    MISSING  $bin"
        missing=1
    fi
done

if [ "$missing" -ne 0 ]; then
    echo "!!  Some tools are missing. Open nvim and run :Mason to see why."
    exit 1
fi
echo "Done. Restart nvim; open a .go file and :LspInfo should show gopls attached."
