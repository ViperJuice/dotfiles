#!/bin/bash
# Bootstrap dotfiles on a new machine
# Safe to run multiple times - uses managed blocks that get replaced on each run

set -e

DOTFILES_DIR="$(cd "$(dirname "$0")" && pwd)"

# Track what was installed/configured for summary
INSTALLED=()
CONFIGURED=()
SKIPPED=()

# Detect platform
detect_platform() {
    if [ -d "/mnt/c/Users" ]; then
        echo "wsl"
    elif [[ "$(uname)" == "Darwin" ]]; then
        echo "mac"
    else
        echo "linux"
    fi
}

PLATFORM=$(detect_platform)

echo "Installing dotfiles from $DOTFILES_DIR..."
echo "Detected platform: $PLATFORM"
echo ""

# =============================================================================
# Dependency Installation
# =============================================================================

install_deps() {
    echo "Checking dependencies..."

    # Git
    if ! command -v git &>/dev/null; then
        echo "  Installing git..."
        if command -v apt &>/dev/null; then
            sudo apt update && sudo apt install -y git
            INSTALLED+=("git")
        elif command -v brew &>/dev/null; then
            brew install git
            INSTALLED+=("git")
        else
            echo "  ⚠ Cannot install git automatically"
            SKIPPED+=("git")
        fi
    else
        echo "  ✓ git"
    fi

    # Python 3
    if ! command -v python3 &>/dev/null; then
        echo "  Installing python3..."
        if command -v apt &>/dev/null; then
            sudo apt install -y python3
            INSTALLED+=("python3")
        elif command -v brew &>/dev/null; then
            brew install python3
            INSTALLED+=("python3")
        else
            echo "  ⚠ Cannot install python3 automatically"
            SKIPPED+=("python3")
        fi
    else
        echo "  ✓ python3"
    fi

    # Node.js / npm (needed for Claude Code CLI)
    if ! command -v npm &>/dev/null; then
        echo "  Installing Node.js/npm..."
        if command -v apt &>/dev/null; then
            sudo apt install -y nodejs npm
            INSTALLED+=("nodejs/npm")
        elif command -v brew &>/dev/null; then
            brew install node
            INSTALLED+=("node")
        else
            echo "  ⚠ Cannot install npm automatically"
            SKIPPED+=("npm")
        fi
    else
        echo "  ✓ npm"
    fi

    # Zsh
    if ! command -v zsh &>/dev/null; then
        echo "  Installing zsh..."
        if command -v apt &>/dev/null; then
            sudo apt install -y zsh
            INSTALLED+=("zsh")
        elif command -v brew &>/dev/null; then
            brew install zsh
            INSTALLED+=("zsh")
        else
            echo "  ⚠ Cannot install zsh automatically"
            SKIPPED+=("zsh")
        fi
    else
        echo "  ✓ zsh"
    fi

    # VS Code
    if ! command -v code &>/dev/null; then
        if command -v apt &>/dev/null && { [ -n "$DISPLAY" ] || [ -n "$WAYLAND_DISPLAY" ]; }; then
            # Desktop machine: install full VS Code via apt repo
            echo "  Installing VS Code (desktop)..."
            if [ ! -f /etc/apt/keyrings/packages.microsoft.gpg ]; then
                wget -qO- https://packages.microsoft.com/keys/microsoft.asc | gpg --dearmor > /tmp/packages.microsoft.gpg
                sudo install -D -o root -g root -m 644 /tmp/packages.microsoft.gpg /etc/apt/keyrings/packages.microsoft.gpg
                echo "deb [arch=amd64,arm64,armhf signed-by=/etc/apt/keyrings/packages.microsoft.gpg] https://packages.microsoft.com/repos/code stable main" | sudo tee /etc/apt/sources.list.d/vscode.list > /dev/null
                sudo apt update -qq
            fi
            sudo apt install -y code 2>/dev/null && INSTALLED+=("code (VS Code)") || SKIPPED+=("code (optional)")
        else
            # Headless server: install standalone CLI (supports tunnels)
            echo "  Installing VS Code CLI (headless)..."
            local vscode_url="https://update.code.visualstudio.com/latest/cli-linux-x64/stable"
            mkdir -p "$HOME/.local/bin"
            curl -sL "$vscode_url" -o /tmp/vscode-cli.tar.gz && tar -xzf /tmp/vscode-cli.tar.gz -C "$HOME/.local/bin" && rm /tmp/vscode-cli.tar.gz && INSTALLED+=("code (CLI)") || SKIPPED+=("code (optional)")
        fi
    else
        echo "  ✓ code"
    fi

    # Cursor
    if ! command -v cursor &>/dev/null; then
        if command -v apt &>/dev/null && { [ -n "$DISPLAY" ] || [ -n "$WAYLAND_DISPLAY" ]; }; then
            # Desktop machine: cursor is typically installed via .deb
            echo "  ℹ Cursor: Install from https://cursor.com/downloads"
            SKIPPED+=("cursor (install manually)")
        else
            # Headless server: install standalone CLI (supports tunnels)
            echo "  Installing Cursor CLI (headless)..."
            local cursor_url="https://api2.cursor.sh/updates/download-latest?os=cli-linux-x64&channel=stable"
            mkdir -p "$HOME/.local/bin"
            curl -sL "$cursor_url" -o /tmp/cursor-cli.tar.gz && tar -xzf /tmp/cursor-cli.tar.gz -C "$HOME/.local/bin" && rm /tmp/cursor-cli.tar.gz && INSTALLED+=("cursor (CLI)") || SKIPPED+=("cursor (optional)")
        fi
    else
        echo "  ✓ cursor"
    fi

    # Claude Code CLI
    if ! command -v claude &>/dev/null; then
        echo "  Installing Claude Code CLI..."
        if command -v npm &>/dev/null; then
            npm install -g @anthropic-ai/claude-code
            INSTALLED+=("claude-code")
        else
            echo "  ⚠ Cannot install Claude Code: npm not found"
            SKIPPED+=("claude-code")
        fi
    else
        echo "  ✓ claude"
    fi

    # Zellij (custom fork with pane targeting features)
    # The custom fork adds --pane-id, --stack-with, focus-pane-by-id, etc.
    ZELLIJ_SRC_DIR="${ZELLIJ_SRC_DIR:-$HOME/code/zellij}"
    ZELLIJ_BRANCH="feat/rename-pane-by-id"

    if [[ -d "$ZELLIJ_SRC_DIR/.git" ]]; then
        echo "  Building custom Zellij from $ZELLIJ_SRC_DIR..."
        # Ensure Rust toolchain is available
        if ! command -v cargo &>/dev/null; then
            if command -v rustup &>/dev/null; then
                echo "    Updating Rust toolchain..."
                rustup update stable
            else
                echo "    Installing Rust via rustup..."
                curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh -s -- -y
                source "$HOME/.cargo/env"
            fi
        fi

        if command -v cargo &>/dev/null; then
            # Checkout the feature branch and build
            (
                cd "$ZELLIJ_SRC_DIR" &&
                git checkout "$ZELLIJ_BRANCH" 2>/dev/null &&
                cargo xtask build 2>&1 | tail -1
            )
            if [[ -f "$ZELLIJ_SRC_DIR/target/release/zellij" ]]; then
                mkdir -p "$HOME/.local/bin"
                # Remove first to avoid "Text file busy" when zellij is running
                rm -f "$HOME/.local/bin/zellij"
                cp "$ZELLIJ_SRC_DIR/target/release/zellij" "$HOME/.local/bin/zellij"
                INSTALLED+=("zellij (custom fork)")
                echo "  ✓ Custom Zellij installed to ~/.local/bin/zellij"
            else
                echo "  ⚠ Custom Zellij build failed - check $ZELLIJ_SRC_DIR"
                SKIPPED+=("zellij (custom build failed)")
            fi
        else
            echo "  ⚠ Cannot build custom Zellij: Rust toolchain not available"
            SKIPPED+=("zellij (no Rust)")
        fi
    elif ! command -v zellij &>/dev/null; then
        echo "  Installing stock Zellij (custom fork not found at $ZELLIJ_SRC_DIR)..."
        echo "  ⚠ Stock Zellij lacks --pane-id and --stack-with features"
        if [[ "$PLATFORM" == "mac" ]] && command -v brew &>/dev/null; then
            brew install zellij
            INSTALLED+=("zellij (stock)")
        elif command -v cargo &>/dev/null; then
            cargo install zellij
            INSTALLED+=("zellij (stock)")
        else
            echo "  ℹ Zellij: Install manually from https://zellij.dev/"
            SKIPPED+=("zellij (optional)")
        fi
    else
        echo "  ✓ zellij"
    fi

    # kitty terminal (OSC 52 clipboard support for SSH + zellij)
    if [[ "$PLATFORM" != "mac" ]]; then
        if ! command -v kitty &>/dev/null; then
            if command -v apt &>/dev/null; then
                echo "  Installing kitty terminal..."
                sudo apt install -y kitty && INSTALLED+=("kitty") || SKIPPED+=("kitty (optional)")
            fi
        else
            echo "  ✓ kitty"
        fi

        # Set kitty as default terminal emulator
        if command -v kitty &>/dev/null && command -v update-alternatives &>/dev/null; then
            KITTY_PATH=$(which kitty)
            if ! update-alternatives --query x-terminal-emulator 2>/dev/null | grep -q "Value: $KITTY_PATH"; then
                echo "  Setting kitty as default terminal..."
                sudo update-alternatives --set x-terminal-emulator "$KITTY_PATH" 2>/dev/null && CONFIGURED+=("kitty as default terminal") || true
            else
                echo "  ✓ kitty is default terminal"
            fi
        fi
    fi

    # Audio playback tools (for notification sounds)
    if [[ "$PLATFORM" != "mac" ]]; then
        if command -v pw-play &>/dev/null; then
            echo "  ✓ pw-play (PipeWire)"
        elif command -v paplay &>/dev/null; then
            echo "  ✓ paplay (PulseAudio)"
        else
            if command -v apt &>/dev/null; then
                if dpkg -l pipewire 2>/dev/null | grep -q '^ii'; then
                    echo "  Installing PipeWire audio tools..."
                    sudo apt install -y pipewire-bin sound-theme-freedesktop 2>/dev/null && INSTALLED+=("pipewire-bin") || SKIPPED+=("audio tools (optional)")
                else
                    echo "  Installing PulseAudio tools..."
                    sudo apt install -y pulseaudio-utils sound-theme-freedesktop 2>/dev/null && INSTALLED+=("pulseaudio-utils") || SKIPPED+=("audio tools (optional)")
                fi
            fi
        fi
    fi

    # Informational checks for other coding tools (not auto-installed)
    echo ""
    echo "Other coding tools:"
    command -v opencode &>/dev/null && echo "  ✓ opencode" || echo "  ℹ opencode: not installed (https://opencode.ai)"
    command -v gemini &>/dev/null && echo "  ✓ gemini" || echo "  ℹ gemini: npm install -g @google/gemini-cli"
    command -v codex &>/dev/null && echo "  ✓ codex" || echo "  ℹ codex: npm install -g @openai/codex"
    command -v cursor &>/dev/null && echo "  ✓ cursor" || { [ -d ~/.cursor ] && echo "  ✓ cursor (config dir exists)" || echo "  ℹ cursor: not installed (https://cursor.com)"; }

    echo ""
}

# Verify required dependencies
verify_deps() {
    local missing=()
    command -v git &>/dev/null || missing+=("git")
    command -v python3 &>/dev/null || missing+=("python3")
    command -v claude &>/dev/null || missing+=("claude")

    if [ ${#missing[@]} -gt 0 ]; then
        echo ""
        echo "❌ ERROR: Required dependencies missing: ${missing[*]}"
        echo ""
        echo "Please install manually:"
        for dep in "${missing[@]}"; do
            case $dep in
                git) echo "  git: sudo apt install git  OR  brew install git" ;;
                python3) echo "  python3: sudo apt install python3  OR  brew install python3" ;;
                claude) echo "  claude: npm install -g @anthropic-ai/claude-code" ;;
            esac
        done
        echo ""
        echo "Then re-run: ./bootstrap.sh"
        exit 1
    fi
}

# Authenticate Claude Code (triggers browser login if needed)
authenticate_claude() {
    echo "Checking Claude Code authentication..."

    # Check if already authenticated by running a simple command
    if claude --version &>/dev/null; then
        # Try to check auth status - if this fails, we need to auth
        if claude /doctor 2>&1 | grep -q "Authenticated"; then
            echo "  ✓ Claude Code authenticated"
            return 0
        fi
    fi

    echo "  Launching Claude Code for authentication..."
    echo "  Please complete the browser authentication when prompted."
    echo ""

    # Run claude interactively to trigger auth flow
    claude --help &>/dev/null || true

    echo ""
    echo "  ✓ Claude Code setup initiated"
    echo "    If not authenticated, run 'claude' to complete login"
}

install_deps
verify_deps

# Set Zsh as default shell
if command -v zsh &>/dev/null; then
    ZSH_PATH=$(which zsh)
    if [[ "$SHELL" != "$ZSH_PATH" ]]; then
        echo "Setting Zsh as default shell..."
        # Ensure zsh is in /etc/shells
        if ! grep -qF "$ZSH_PATH" /etc/shells 2>/dev/null; then
            echo "$ZSH_PATH" | sudo tee -a /etc/shells >/dev/null
        fi
        sudo chsh -s "$ZSH_PATH" "$USER" && CONFIGURED+=("zsh as default shell") || SKIPPED+=("zsh default (chsh failed)")
    fi
fi

authenticate_claude
echo ""

# =============================================================================
# Update Git Submodules (anthropic-skills marketplace)
# =============================================================================
echo "Updating git submodules..."
git -C "$DOTFILES_DIR" submodule update --init --remote
echo "  ✓ Submodules updated"
echo ""

# Helper: Add or replace a managed block in a file
# Usage: add_managed_block <file> <block_name> <content>
add_managed_block() {
    local file="$1"
    local block_name="$2"
    local content="$3"

    local start_marker="# BEGIN DOTFILES: $block_name"
    local end_marker="# END DOTFILES: $block_name"

    [ -f "$file" ] || return 0

    # Remove existing block if present (using temp file for compatibility)
    local tmp
    tmp=$(mktemp)
    awk -v start="$start_marker" -v end="$end_marker" '
        $0 == start { skip=1; next }
        $0 == end { skip=0; next }
        !skip { print }
    ' "$file" > "$tmp" && mv "$tmp" "$file"

    # Add new block
    cat >> "$file" << EOF

$start_marker
$content
$end_marker
EOF
    echo "Updated $block_name in $file"
}

# Create ~/.claude if it doesn't exist
mkdir -p ~/.claude

# Symlink Claude config files (ln -sf to files is safe)
ln -sf "$DOTFILES_DIR/claude-config/settings.json" ~/.claude/settings.json
ln -sf "$DOTFILES_DIR/claude-config/statusline-custom.sh" ~/.claude/statusline-custom.sh
ln -sf "$DOTFILES_DIR/claude-config/notify.sh" ~/.claude/notify.sh
ln -sf "$DOTFILES_DIR/claude-config/notify-clear.sh" ~/.claude/notify-clear.sh
ln -sf "$DOTFILES_DIR/claude-config/agent-pane.sh" ~/.claude/agent-pane.sh
ln -sf "$DOTFILES_DIR/claude-config/bash-pane.sh" ~/.claude/bash-pane.sh
ln -sf "$DOTFILES_DIR/claude-config/stacked-pane.sh" ~/.claude/stacked-pane.sh
ln -sf "$DOTFILES_DIR/claude-config/AGENTS.md" ~/.claude/AGENTS.md
ln -sf "$DOTFILES_DIR/claude-config/CLAUDE.md" ~/.claude/CLAUDE.md
ln -sf "$DOTFILES_DIR/scripts/editor-remote.sh" ~/.claude/editor-remote.sh
ln -sf "$DOTFILES_DIR/claude-config/gateway-guidance.yaml" ~/.claude/gateway-guidance.yaml
# Symlink commands + agents: shared + claude-specific
mkdir -p ~/.claude/commands
# Clear stale symlinks (preserves manually-created commands)
for entry in ~/.claude/commands/*; do
    [ -L "$entry" ] && rm -f "$entry"
done
for cmd in "$DOTFILES_DIR/shared/commands/"*.md "$DOTFILES_DIR/shared/agents/"*.md "$DOTFILES_DIR/claude-config/commands/"*.md; do
    [ -f "$cmd" ] && ln -sf "$cmd" ~/.claude/commands/
done
chmod +x ~/.claude/statusline-custom.sh ~/.claude/notify.sh ~/.claude/notify-clear.sh ~/.claude/agent-pane.sh ~/.claude/bash-pane.sh ~/.claude/stacked-pane.sh
echo "Linked Claude config files"

# OpenCode: shared + opencode-specific commands
mkdir -p ~/.config/opencode/commands
# Clear stale symlinks
for entry in ~/.config/opencode/commands/*; do
    [ -L "$entry" ] && rm -f "$entry"
done
for cmd in "$DOTFILES_DIR/shared/commands/"*.md "$DOTFILES_DIR/opencode-config/commands/"*.md; do
    [ -f "$cmd" ] && ln -sf "$cmd" ~/.config/opencode/commands/
done

# OpenCode: shared + opencode-specific agents
mkdir -p ~/.config/opencode/agent
for entry in ~/.config/opencode/agent/*; do
    [ -L "$entry" ] && rm -f "$entry"
done
for agent in "$DOTFILES_DIR/shared/agents/"*.md "$DOTFILES_DIR/opencode-config/agents/"*.md; do
    [ -f "$agent" ] && ln -sf "$agent" ~/.config/opencode/agent/
done
echo "Linked OpenCode commands and agents"

# Install PMCP configuration with expanded paths
if [ -f "$DOTFILES_DIR/.pmcp.json" ]; then
    # Expand $HOME in the config and write to ~/.pmcp.json
    # Use double quotes and eval to properly expand $HOME
    while IFS= read -r line; do
        echo "$line" | sed "s|\\\$HOME|$HOME|g"
    done < "$DOTFILES_DIR/.pmcp.json" > ~/.pmcp.json
    echo "Installed PMCP configuration to ~/.pmcp.json"
    CONFIGURED+=("PMCP gateway config")
fi

# Install MCP configuration (Claude Code gateway entry point)
if [ -f "$DOTFILES_DIR/.mcp.json" ]; then
    cp "$DOTFILES_DIR/.mcp.json" ~/.mcp.json
    echo "Installed MCP configuration to ~/.mcp.json"
    CONFIGURED+=("MCP gateway entry point")
fi

# =============================================================================
# Gemini CLI Configuration
# =============================================================================

if command -v gemini &>/dev/null || [ -d ~/.gemini ]; then
    mkdir -p ~/.gemini

    # Generate GEMINI.md: header + shared core instructions
    {
        echo "# Development Instructions for Gemini CLI"
        echo ""
        echo "<!-- Generated by bootstrap.sh from shared/instructions/core.md -->"
        echo "<!-- Do not edit directly — update shared/instructions/core.md instead -->"
        echo ""
        cat "$DOTFILES_DIR/shared/instructions/core.md"
    } > ~/.gemini/GEMINI.md

    # Merge mcpServers into existing Gemini settings.json (preserves auth config)
    python3 -c "
import json, os, sys

settings_path = os.path.expanduser('~/.gemini/settings.json')
try:
    with open(settings_path) as f:
        settings = json.load(f)
except (FileNotFoundError, json.JSONDecodeError):
    settings = {}

pmcp_config = os.path.expanduser('~/.pmcp.json')
settings['mcpServers'] = {
    'gateway': {
        'command': 'uvx',
        'args': ['pmcp', '-c', pmcp_config]
    }
}
settings.setdefault('general', {}).setdefault('previewFeatures', True)

with open(settings_path, 'w') as f:
    json.dump(settings, f, indent=2)
    f.write('\n')
" 2>/dev/null

    echo "Configured Gemini CLI (instructions + MCP gateway)"
    CONFIGURED+=("Gemini CLI")
fi

# =============================================================================
# Cursor IDE Configuration
# =============================================================================

if command -v cursor &>/dev/null || [ -d ~/.cursor ]; then
    mkdir -p ~/.cursor/rules

    # Generate core-instructions.mdc: YAML frontmatter + shared core instructions
    {
        echo "---"
        echo "description: Core development instructions shared across all coding tools"
        echo "alwaysApply: true"
        echo "---"
        echo ""
        cat "$DOTFILES_DIR/shared/instructions/core.md"
    } > ~/.cursor/rules/core-instructions.mdc

    # Generate Cursor MCP config pointing at PMCP gateway
    PMCP_CONFIG="$HOME/.pmcp.json"
    cat > ~/.cursor/mcp.json << MCPEOF
{
  "mcpServers": {
    "gateway": {
      "command": "uvx",
      "args": ["pmcp", "-c", "$PMCP_CONFIG"]
    }
  }
}
MCPEOF

    echo "Configured Cursor IDE (rules + MCP gateway)"
    CONFIGURED+=("Cursor IDE")
fi

# =============================================================================
# OpenCode MCP Configuration
# =============================================================================

if command -v opencode &>/dev/null || [ -d ~/.config/opencode ]; then
    OPENCODE_CONFIG="$HOME/.config/opencode/opencode.json"
    PMCP_CONFIG="$HOME/.pmcp.json"

    # Merge MCP config into existing opencode.json (preserves other settings)
    python3 -c "
import json, os

config_path = os.path.expanduser('$OPENCODE_CONFIG')
try:
    with open(config_path) as f:
        config = json.load(f)
except (FileNotFoundError, json.JSONDecodeError):
    config = {}

config['\$schema'] = 'https://opencode.ai/config.json'
config['mcp'] = {
    'gateway': {
        'type': 'local',
        'command': ['uvx', 'pmcp', '-c', os.path.expanduser('$PMCP_CONFIG')],
        'enabled': True
    }
}
plugins = config.get('plugin', [])
if 'opencode-gemini-auth@latest' not in plugins:
    plugins.append('opencode-gemini-auth@latest')
config['plugin'] = plugins

os.makedirs(os.path.dirname(config_path), exist_ok=True)
with open(config_path, 'w') as f:
    json.dump(config, f, indent=2)
    f.write('\n')
" 2>/dev/null

    echo "Configured OpenCode MCP gateway"
    CONFIGURED+=("OpenCode MCP")
fi

# =============================================================================
# OpenCode Runtime Isolation (oc wrapper)
# =============================================================================

if command -v opencode &>/dev/null || [ -d ~/.config/opencode ]; then
    # Symlink oc tools to ~/.local/bin
    mkdir -p ~/.local/bin
    for tool in oc oc-audit oc-registry oc-cleanup; do
        ln -sf "$DOTFILES_DIR/opencode-config/bin/$tool" ~/.local/bin/"$tool"
    done

    # Create registry directory
    mkdir -p ~/.opencode/repos

    echo "Installed OpenCode runtime tools (oc, oc-audit, oc-registry, oc-cleanup)"
    CONFIGURED+=("OpenCode Runtime")

    # Resource hardening: inotify watches and instances
    SYSCTL_CONF="/etc/sysctl.d/90-opencode.conf"
    INOTIFY_WATCHES=$(cat /proc/sys/fs/inotify/max_user_watches 2>/dev/null || echo 0)
    INOTIFY_INSTANCES=$(cat /proc/sys/fs/inotify/max_user_instances 2>/dev/null || echo 0)

    if [[ "$INOTIFY_WATCHES" -lt 1048576 ]] || [[ "$INOTIFY_INSTANCES" -lt 1024 ]]; then
        echo "  inotify limits are low (watches=$INOTIFY_WATCHES, instances=$INOTIFY_INSTANCES)"
        if command -v sudo &>/dev/null; then
            echo "  Writing $SYSCTL_CONF (requires sudo)..."
            sudo tee "$SYSCTL_CONF" > /dev/null 2>&1 << 'SYSCTL' || {
fs.inotify.max_user_watches=1048576
fs.inotify.max_user_instances=1024
SYSCTL
                echo "  ⚠ Could not write sysctl config (no sudo access)"
                SKIPPED+=("inotify hardening")
            }
            if [[ -f "$SYSCTL_CONF" ]]; then
                sudo sysctl --system > /dev/null 2>&1 || true
                echo "  ✓ inotify limits updated"
                CONFIGURED+=("inotify hardening")
            fi
        else
            echo "  ⚠ sudo not available — manually set inotify limits"
            SKIPPED+=("inotify hardening")
        fi
    fi

    # Run post-install diagnostic
    if command -v oc-audit &>/dev/null || [[ -x "$DOTFILES_DIR/opencode-config/bin/oc-audit" ]]; then
        echo ""
        echo "Running OpenCode audit..."
        "$DOTFILES_DIR/opencode-config/bin/oc-audit" || true
        echo ""
    fi
fi

# Zellij config
mkdir -p ~/.config/zellij
ln -sf "$DOTFILES_DIR/zellij/config.kdl" ~/.config/zellij/config.kdl
ln -sf "$DOTFILES_DIR/zellij/layouts" ~/.config/zellij/layouts
echo "Linked Zellij config"

# WSL: Detect Windows username and symlink Screenshots folder
if [ -d "/mnt/c/Users" ]; then
    WIN_USER=$(cmd.exe /c "echo %USERNAME%" 2>/dev/null | tr -d '\r\n')
    if [ -z "$WIN_USER" ]; then
        # Fallback: find first non-system user in /mnt/c/Users
        WIN_USER=$(ls /mnt/c/Users | grep -vE '^(Default|Public|All Users|Default User)$' | head -1)
    fi
    # Try OneDrive first (common for synced screenshots), then local Pictures
    SCREENSHOTS_WIN="/mnt/c/Users/$WIN_USER/OneDrive/Pictures/Screenshots"
    if [ ! -d "$SCREENSHOTS_WIN" ]; then
        SCREENSHOTS_WIN="/mnt/c/Users/$WIN_USER/Pictures/Screenshots"
    fi
    if [ -d "$SCREENSHOTS_WIN" ]; then
        # Remove first to avoid nested symlink issue
        rm -f ~/screenshots 2>/dev/null
        ln -sf "$SCREENSHOTS_WIN" ~/screenshots
        echo "Linked Windows Screenshots to ~/screenshots"
    fi
fi

# (pulseaudio-utils now handled in install_deps above)

# Define PATH config content
read -r -d '' PATH_CONFIG << 'EOF' || true
# Rust/Cargo environment
[ -f "$HOME/.cargo/env" ] && . "$HOME/.cargo/env"

# Add local bin and Claude local bin to PATH
export PATH="$HOME/.local/bin:$HOME/.claude/local:$PATH"

# Display host for remote editor wrappers (Tailscale hostname)
export DOTFILES_DISPLAY_HOST="display"

# Initialize nvm (Node Version Manager)
export NVM_DIR="$HOME/.nvm"
[ -s "$NVM_DIR/nvm.sh" ] && \. "$NVM_DIR/nvm.sh"
[ -s "$NVM_DIR/bash_completion" ] && \. "$NVM_DIR/bash_completion"
EOF

# Define 1Password shell integration content
read -r -d '' OP_CONFIG << 'EOF' || true
# 1Password SSH Agent
if [ -S "$HOME/.1password/agent.sock" ]; then
    export SSH_AUTH_SOCK="$HOME/.1password/agent.sock"
fi

# 1Password CLI shell integration (op plugin)
if command -v op &>/dev/null; then
    # Only attempt signin when 1Password app integration is available
    if [ -S "$HOME/.1password/agent.sock" ]; then
        eval "$(op signin --account my </dev/null 2>/dev/null)" || true
    fi
    # Helper: load secrets from 1Password into env
    op-env() {
        local envfile="${1:-$DOTFILES_DIR/1password/env.op}"
        if [ -f "$envfile" ]; then
            eval "$(op run --env-file="$envfile" -- env | grep -E '^(ANTHROPIC|CEREBRAS|GROQ|BRIGHTDATA|OLLAMA|OPENAI|GOOGLE)_')"
            echo "✓ Loaded secrets from 1Password"
        else
            echo "No env.op file found at $envfile"
        fi
    }
fi
EOF

# =============================================================================
# 1Password Integration
# =============================================================================

if [ -f "$DOTFILES_DIR/1password/setup.sh" ]; then
    source "$DOTFILES_DIR/1password/setup.sh"
    CONFIGURED+=("1Password SSH agent + git signing")
fi

# Skills installation (platform-specific; Claude + Codex)
mkdir -p ~/.claude/skills ~/.codex/skills

# Clear stale skill symlinks (e.g. after username/path changes).
# Keep any real directories/files so local custom skills aren't destroyed.
for skills_dir in ~/.claude/skills ~/.codex/skills; do
    if [ -d "$skills_dir" ]; then
        for entry in "$skills_dir"/*; do
            [ -L "$entry" ] && rm -f "$entry" || true
        done

        # Also remove broken symlinks nested anywhere under the skills dir.
        # This is safe for local custom skills and avoids leaving dangling links.
        if command -v find &>/dev/null; then
            find "$skills_dir" -type l ! -exec test -e {} \; -exec rm -f {} + 2>/dev/null || true
        fi
    fi
done

# Install dotfiles-local skills (idempotent symlinks).
if [ -d "$DOTFILES_DIR/claude-config/skills" ]; then
    echo "Installing dotfiles local skills..."
    for skill_dir in "$DOTFILES_DIR/claude-config/skills/"*/; do
        [ -d "$skill_dir" ] || continue
        skill_name=$(basename "$skill_dir")

        # WSL-only skill: don't link on non-WSL.
        if [[ "$skill_name" == "wsl-screenshots" && "$PLATFORM" != "wsl" ]]; then
            continue
        fi

        ln -sf "$skill_dir" ~/.claude/skills/"$skill_name"
        ln -sf "$skill_dir" ~/.codex/skills/"$skill_name"
    done
    echo "  ✓ Installed dotfiles local skills"
fi

if [[ "$PLATFORM" == "wsl" ]]; then
    # WSL-specific skills
    ln -sf "$DOTFILES_DIR/claude-config/skills/wsl-screenshots" ~/.claude/skills/wsl-screenshots
    ln -sf "$DOTFILES_DIR/claude-config/skills/wsl-screenshots" ~/.codex/skills/wsl-screenshots
    echo "Installed WSL-specific skills (wsl-screenshots)"
fi

# Install anthropic-skills (symlink each skill to ~/.claude/skills and ~/.codex/skills)
if [ -d "$DOTFILES_DIR/anthropic-skills/skills" ]; then
    echo "Installing Anthropic skills..."
    for skill_dir in "$DOTFILES_DIR/anthropic-skills/skills/"*/; do
        skill_name=$(basename "$skill_dir")
        ln -sf "$skill_dir" ~/.claude/skills/"$skill_name"
        ln -sf "$skill_dir" ~/.codex/skills/"$skill_name"
    done
    echo "  ✓ Installed $(ls -d "$DOTFILES_DIR/anthropic-skills/skills/"*/ | wc -l) Anthropic skills"
fi

# Define shell config content
read -r -d '' CLAUDE_CONFIG << 'EOF' || true
# Claude Code alias with permissions bypass
alias claude="claude --allow-dangerously-skip-permissions"

# Prevent Claude Code from overwriting terminal tab title
export CLAUDE_CODE_DISABLE_TERMINAL_TITLE=1
EOF

read -r -d '' EDITOR_REMOTE << 'EOF' || true
# Remote editor wrappers (cursor/code work seamlessly over SSH)
if [ -f "$HOME/.claude/editor-remote.sh" ]; then
    source "$HOME/.claude/editor-remote.sh"
fi
EOF

read -r -d '' ZSH_TABTITLE << 'EOF' || true
# Update terminal + Zellij pane title to current git repo:branch or directory name
function precmd() {
  local worktree=$(git rev-parse --show-toplevel 2>/dev/null)
  local repo=$(basename "$worktree" 2>/dev/null)
  local branch=$(git branch --show-current 2>/dev/null)
  local title

  if [[ -n "$repo" && -n "$branch" ]]; then
    title="${repo}:${branch}"
  elif [[ -n "$repo" ]]; then
    title="$repo"
  else
    title="${PWD##*/}"
  fi
  echo -ne "\033]0;${title}\007"
  # Also set Zellij pane title (auto-updates on branch change, cd, TUI exit)
  [[ -n "$ZELLIJ" ]] && command zellij action rename-pane -p "$ZELLIJ_PANE_ID" "$title" 2>/dev/null
  # Store session root for notification scripts (frozen when agent takes over)
  if [[ -n "$ZELLIJ_PANE_ID" ]]; then
    local session_dir="${XDG_CACHE_HOME:-$HOME/.cache}/claude-dotfiles/pane-session"
    [[ -d "$session_dir" ]] || mkdir -p "$session_dir" 2>/dev/null
    echo "${worktree:-$PWD}" > "$session_dir/$ZELLIJ_PANE_ID" 2>/dev/null
  fi
}

# Prevent Oh My Zsh from overriding the custom tab title
DISABLE_AUTO_TITLE="true"
EOF

read -r -d '' BASH_TABTITLE << 'EOF' || true
# Update terminal + Zellij pane title to current git repo:branch or directory name
set_tab_title() {
  local worktree=$(git rev-parse --show-toplevel 2>/dev/null)
  local repo=$(basename "$worktree" 2>/dev/null)
  local branch=$(git branch --show-current 2>/dev/null)
  local title

  if [[ -n "$repo" && -n "$branch" ]]; then
    title="${repo}:${branch}"
  elif [[ -n "$repo" ]]; then
    title="$repo"
  else
    title="$(basename "$PWD")"
  fi
  echo -ne "\033]0;${title}\007"
  # Also set Zellij pane title (auto-updates on branch change, cd, TUI exit)
  [[ -n "$ZELLIJ" ]] && command zellij action rename-pane -p "$ZELLIJ_PANE_ID" "$title" 2>/dev/null
  # Store session root for notification scripts (frozen when agent takes over)
  if [[ -n "$ZELLIJ_PANE_ID" ]]; then
    local session_dir="${XDG_CACHE_HOME:-$HOME/.cache}/claude-dotfiles/pane-session"
    [[ -d "$session_dir" ]] || mkdir -p "$session_dir" 2>/dev/null
    echo "${worktree:-$PWD}" > "$session_dir/$ZELLIJ_PANE_ID" 2>/dev/null
  fi
}
PROMPT_COMMAND="set_tab_title${PROMPT_COMMAND:+;$PROMPT_COMMAND}"
EOF

# Ensure shell rc files exist before adding managed blocks
touch ~/.zshrc ~/.bashrc 2>/dev/null

# Add managed blocks to shell configs
for rc in ~/.bashrc ~/.zshrc; do
    [ -f "$rc" ] && add_managed_block "$rc" "PATH_CONFIG" "$PATH_CONFIG"
    [ -f "$rc" ] && add_managed_block "$rc" "CLAUDE_CONFIG" "$CLAUDE_CONFIG"
    [ -f "$rc" ] && add_managed_block "$rc" "EDITOR_REMOTE" "$EDITOR_REMOTE"
done

[ -f ~/.zshrc ] && add_managed_block ~/.zshrc "TABTITLE" "$ZSH_TABTITLE"
[ -f ~/.bashrc ] && add_managed_block ~/.bashrc "TABTITLE" "$BASH_TABTITLE"

# 1Password shell integration
for rc in ~/.bashrc ~/.zshrc; do
    [ -f "$rc" ] && add_managed_block "$rc" "1PASSWORD" "$OP_CONFIG"
done

# =============================================================================
# Obsidian Dev Docs Sync
# =============================================================================

# Symlink sync script (rm first to avoid ln -sf quirks with existing symlinks)
rm -f ~/.claude/sync-obsidian-docs.sh
ln -s "$DOTFILES_DIR/claude-config/sync-obsidian-docs.sh" ~/.claude/sync-obsidian-docs.sh
chmod +x ~/.claude/sync-obsidian-docs.sh 2>/dev/null || true

# Create obsidian vault directory if it doesn't exist
mkdir -p ~/code/obsidian-dev-docs

# Install cron job for hourly sync (idempotent)
CRON_CMD="0 * * * * $HOME/.claude/sync-obsidian-docs.sh --quiet"
if ! crontab -l 2>/dev/null | grep -qF "sync-obsidian-docs.sh"; then
    (crontab -l 2>/dev/null; echo "$CRON_CMD") | crontab -
    echo "Installed hourly cron job for obsidian-docs sync"
    CONFIGURED+=("obsidian-docs cron")
else
    echo "Cron job for obsidian-docs sync already installed"
fi

# Run initial sync (non-fatal if script missing or obsidian vault not configured)
~/.claude/sync-obsidian-docs.sh 2>/dev/null || echo "  ℹ Obsidian sync skipped (run manually: ~/.claude/sync-obsidian-docs.sh)"

# =============================================================================
# Summary
# =============================================================================

echo ""
echo "✅ Dotfiles installed successfully!"
echo ""

if [ ${#INSTALLED[@]} -gt 0 ]; then
    echo "Installed:"
    for item in "${INSTALLED[@]}"; do
        echo "  • $item"
    done
    echo ""
fi

echo "Configured:"
echo "  • Claude Code → ~/.claude/ (settings, commands, skills)"
echo "  • Shell aliases → ~/.zshrc / ~/.bashrc"
echo "  • Tab title → repo:branch format"
if command -v zellij &>/dev/null; then
    echo "  • Zellij notifications → enabled"
fi
if [ -d "$DOTFILES_DIR/anthropic-skills" ]; then
    echo "  • Anthropic skills marketplace → available"
fi
# Show which additional tools were configured
for tool in "${CONFIGURED[@]}"; do
    case "$tool" in
        "Gemini CLI"|"Cursor IDE"|"OpenCode MCP")
            echo "  • $tool"
            ;;
    esac
done

if [ ${#SKIPPED[@]} -gt 0 ]; then
    echo ""
    echo "Skipped (install manually if needed):"
    for item in "${SKIPPED[@]}"; do
        echo "  • $item"
    done
fi

echo ""
echo "Platform: $PLATFORM"
echo ""
echo "Next step: Restart your shell"
echo "  source ~/.zshrc  # or ~/.bashrc"
