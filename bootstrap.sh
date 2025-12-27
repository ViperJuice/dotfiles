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

echo "Claude dotfiles installed!"
