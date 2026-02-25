#!/bin/bash
# 1Password integration setup
# Called by bootstrap.sh - sets up SSH agent, git signing, and secret injection
# Requires: 1password desktop app + 1password-cli installed

set -e

DOTFILES_DIR="${DOTFILES_DIR:-$(cd "$(dirname "$0")/.." && pwd)}"

# Check if op CLI is available
if ! command -v op &>/dev/null; then
    echo "  ⚠ 1Password CLI (op) not installed — skipping 1Password setup"
    echo "  Install: https://developer.1password.com/docs/cli/get-started/"
    return 0 2>/dev/null || exit 0
fi

echo "Setting up 1Password integration..."

# =========================================================================
# SSH Agent
# =========================================================================

# 1Password SSH agent socket location (Linux)
OP_SSH_SOCK="$HOME/.1password/agent.sock"

# Create SSH config directory
mkdir -p ~/.ssh
chmod 700 ~/.ssh

# Create/update SSH config for 1Password agent
SSH_CONFIG=~/.ssh/config
if [ ! -f "$SSH_CONFIG" ]; then
    touch "$SSH_CONFIG"
    chmod 600 "$SSH_CONFIG"
fi

# Add 1Password SSH agent identity agent if not already present
if ! grep -q "IdentityAgent.*1password" "$SSH_CONFIG" 2>/dev/null; then
    cat >> "$SSH_CONFIG" << EOF

# 1Password SSH Agent
Host *
    IdentityAgent ~/.1password/agent.sock
EOF
    echo "  ✓ SSH config updated with 1Password agent"
else
    echo "  ✓ SSH config already has 1Password agent"
fi

# =========================================================================
# Git Commit Signing
# =========================================================================

# Configure git to use SSH signing via 1Password
git config --global gpg.format ssh
git config --global gpg.ssh.program "/opt/1Password/op-ssh-sign"
git config --global commit.gpgsign true
git config --global tag.gpgsign true

# Create allowed_signers file (user needs to add their public key)
ALLOWED_SIGNERS=~/.ssh/allowed_signers
if [ ! -f "$ALLOWED_SIGNERS" ]; then
    touch "$ALLOWED_SIGNERS"
    echo "  ℹ Created ~/.ssh/allowed_signers — add your signing key with:"
    echo "    op read 'op://Personal/SSH Key/public key' >> ~/.ssh/allowed_signers"
fi
git config --global gpg.ssh.allowedSignersFile "$ALLOWED_SIGNERS"

echo "  ✓ Git commit signing configured (SSH via 1Password)"

# =========================================================================
# Shell Integration (op plugin for CLI tools)
# =========================================================================

echo "  ✓ 1Password integration complete"
echo ""
echo "  Next steps:"
echo "    1. Open 1Password desktop app and enable:"
echo "       Settings → Developer → SSH Agent"
echo "       Settings → Developer → CLI Integration (biometric unlock)"
echo "    2. Sign in: op signin"
echo "    3. Import secrets: $DOTFILES_DIR/1password/import-secrets.sh"
