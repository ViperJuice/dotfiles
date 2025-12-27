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

echo "Claude dotfiles installed!"
