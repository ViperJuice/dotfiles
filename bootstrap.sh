#!/bin/bash
# Bootstrap dotfiles on a new machine

set -e

DOTFILES_DIR="$(cd "$(dirname "$0")" && pwd)"

echo "Installing dotfiles from $DOTFILES_DIR..."

# Create ~/.claude if it doesn't exist
mkdir -p ~/.claude

# Symlink Claude config files
ln -sf "$DOTFILES_DIR/claude/settings.json" ~/.claude/settings.json
ln -sf "$DOTFILES_DIR/claude/statusline-custom.sh" ~/.claude/statusline-custom.sh
chmod +x ~/.claude/statusline-custom.sh

# Add Claude alias to shell configs (idempotent)
ALIAS_LINE='alias claude="claude --dangerously-skip-permissions"'
ALIAS_COMMENT='# Claude Code with dangerous permissions bypass'

for rc in ~/.bashrc ~/.zshrc; do
    if [ -f "$rc" ] && ! grep -q "dangerously-skip-permissions" "$rc"; then
        echo -e "\n$ALIAS_COMMENT\n$ALIAS_LINE" >> "$rc"
        echo "Added Claude alias to $rc"
    fi
done

# Add terminal tab title config for WSL/Windows Terminal (idempotent)
# Shows git repo name or falls back to folder name

if [ -f ~/.zshrc ] && ! grep -q "Windows Terminal tab title" ~/.zshrc; then
    cat >> ~/.zshrc << 'ZSHEOF'

# Update Windows Terminal tab title to current git repo or directory name
function precmd() {
  local title=$(basename $(git rev-parse --show-toplevel 2>/dev/null) 2>/dev/null || echo ${PWD##*/})
  echo -ne "\033]0;${title}\007"
}

# Prevent Oh My Zsh from overriding the custom tab title
DISABLE_AUTO_TITLE="true"
ZSHEOF
    echo "Added terminal tab title config to ~/.zshrc"
fi

if [ -f ~/.bashrc ] && ! grep -q "Windows Terminal tab title" ~/.bashrc; then
    cat >> ~/.bashrc << 'BASHEOF'

# Update Windows Terminal tab title to current git repo or directory name
set_tab_title() {
  local title=$(basename $(git rev-parse --show-toplevel 2>/dev/null) 2>/dev/null || basename "$PWD")
  echo -ne "\033]0;${title}\007"
}
PROMPT_COMMAND="set_tab_title${PROMPT_COMMAND:+;$PROMPT_COMMAND}"
BASHEOF
    echo "Added terminal tab title config to ~/.bashrc"
fi

echo "Claude dotfiles installed!"
