#!/bin/bash
# Bootstrap dotfiles on a new machine
# Safe to run multiple times - uses managed blocks that get replaced on each run

set -e

DOTFILES_DIR="$(cd "$(dirname "$0")" && pwd)"

echo "Installing dotfiles from $DOTFILES_DIR..."

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
ln -sf "$DOTFILES_DIR/claude/settings.json" ~/.claude/settings.json
ln -sf "$DOTFILES_DIR/claude/statusline-custom.sh" ~/.claude/statusline-custom.sh
ln -sf "$DOTFILES_DIR/claude/AGENTS.md" ~/.claude/AGENTS.md
ln -sf "$DOTFILES_DIR/claude/CLAUDE.md" ~/.claude/CLAUDE.md
chmod +x ~/.claude/statusline-custom.sh
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

# Define shell config content
read -r -d '' CLAUDE_CONFIG << 'EOF' || true
# Claude Code alias with permissions bypass
alias claude="claude --dangerously-skip-permissions"

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
    [ -f "$rc" ] && add_managed_block "$rc" "CLAUDE_CONFIG" "$CLAUDE_CONFIG"
done

[ -f ~/.zshrc ] && add_managed_block ~/.zshrc "TABTITLE" "$ZSH_TABTITLE"
[ -f ~/.bashrc ] && add_managed_block ~/.bashrc "TABTITLE" "$BASH_TABTITLE"

echo ""
echo "Dotfiles installed! Restart your shell or run: source ~/.zshrc"
