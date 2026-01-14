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

    # Zellij (optional but recommended)
    if ! command -v zellij &>/dev/null; then
        echo "  Installing Zellij..."
        if [[ "$PLATFORM" == "mac" ]] && command -v brew &>/dev/null; then
            brew install zellij
            INSTALLED+=("zellij")
        elif command -v cargo &>/dev/null; then
            cargo install zellij
            INSTALLED+=("zellij")
        else
            echo "  ℹ Zellij: Install manually from https://zellij.dev/"
            SKIPPED+=("zellij (optional)")
        fi
    else
        echo "  ✓ zellij"
    fi

    # pulseaudio-utils (for audio on Linux/WSL)
    if [[ "$PLATFORM" != "mac" ]]; then
        if ! command -v paplay &>/dev/null; then
            if command -v apt &>/dev/null; then
                echo "  Installing pulseaudio-utils..."
                sudo apt install -y pulseaudio-utils 2>/dev/null && INSTALLED+=("pulseaudio-utils") || SKIPPED+=("pulseaudio-utils (optional)")
            fi
        else
            echo "  ✓ paplay"
        fi
    fi

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
    local tmp=$(mktemp)
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
ln -sf "$DOTFILES_DIR/claude-config/AGENTS.md" ~/.claude/AGENTS.md
ln -sf "$DOTFILES_DIR/claude-config/CLAUDE.md" ~/.claude/CLAUDE.md
chmod +x ~/.claude/statusline-custom.sh ~/.claude/notify.sh ~/.claude/notify-clear.sh ~/.claude/agent-pane.sh ~/.claude/bash-pane.sh
echo "Linked Claude config files"

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

# Add Claude local bin to PATH
export PATH="$HOME/.claude/local:$PATH"

# Initialize nvm (Node Version Manager)
export NVM_DIR="$HOME/.nvm"
[ -s "$NVM_DIR/nvm.sh" ] && \. "$NVM_DIR/nvm.sh"
[ -s "$NVM_DIR/bash_completion" ] && \. "$NVM_DIR/bash_completion"
EOF

# Skills installation (platform-specific)
mkdir -p ~/.claude/skills

if [[ "$PLATFORM" == "wsl" ]]; then
    # WSL-specific skills
    ln -sf "$DOTFILES_DIR/claude-config/skills/wsl-screenshots" ~/.claude/skills/wsl-screenshots
    echo "Installed WSL-specific skills (wsl-screenshots)"
fi

# Install anthropic-skills (symlink each skill to ~/.claude/skills/)
if [ -d "$DOTFILES_DIR/anthropic-skills/skills" ]; then
    echo "Installing Anthropic skills..."
    for skill_dir in "$DOTFILES_DIR/anthropic-skills/skills/"*/; do
        skill_name=$(basename "$skill_dir")
        ln -sf "$skill_dir" ~/.claude/skills/"$skill_name"
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

read -r -d '' ZSH_TABTITLE << 'EOF' || true
# Update Windows Terminal tab title to current git repo:branch or directory name
function precmd() {
  local repo=$(basename $(git rev-parse --show-toplevel 2>/dev/null) 2>/dev/null)
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
}

# Prevent Oh My Zsh from overriding the custom tab title
DISABLE_AUTO_TITLE="true"
EOF

read -r -d '' BASH_TABTITLE << 'EOF' || true
# Update Windows Terminal tab title to current git repo:branch or directory name
set_tab_title() {
  local repo=$(basename $(git rev-parse --show-toplevel 2>/dev/null) 2>/dev/null)
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
}
PROMPT_COMMAND="set_tab_title${PROMPT_COMMAND:+;$PROMPT_COMMAND}"
EOF

# Add managed blocks to shell configs
for rc in ~/.bashrc ~/.zshrc; do
    [ -f "$rc" ] && add_managed_block "$rc" "PATH_CONFIG" "$PATH_CONFIG"
    [ -f "$rc" ] && add_managed_block "$rc" "CLAUDE_CONFIG" "$CLAUDE_CONFIG"
done

[ -f ~/.zshrc ] && add_managed_block ~/.zshrc "TABTITLE" "$ZSH_TABTITLE"
[ -f ~/.bashrc ] && add_managed_block ~/.bashrc "TABTITLE" "$BASH_TABTITLE"

# =============================================================================
# Obsidian Dev Docs Sync
# =============================================================================

# Symlink sync script
ln -sf "$DOTFILES_DIR/claude-config/sync-obsidian-docs.sh" ~/.claude/sync-obsidian-docs.sh
chmod +x ~/.claude/sync-obsidian-docs.sh

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

# Run initial sync
~/.claude/sync-obsidian-docs.sh

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
echo "  • Claude Code settings → ~/.claude/"
echo "  • Shell aliases → ~/.zshrc / ~/.bashrc"
echo "  • Tab title → repo:branch format"
if command -v zellij &>/dev/null; then
    echo "  • Zellij notifications → enabled"
fi
if [ -d "$DOTFILES_DIR/anthropic-skills" ]; then
    echo "  • Anthropic skills marketplace → available"
fi

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
