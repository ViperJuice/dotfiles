#!/usr/bin/env bash
# Install/upgrade upstream Zellij to a specific version.
# Run this AFTER all Zellij sessions are killed, then restart Zellij.
#
# Usage:  install-zellij-upstream.sh [version]
# Default version: v0.44.1

set -euo pipefail

VERSION="${1:-v0.44.1}"
TARGET_DIR="${ZELLIJ_INSTALL_DIR:-$HOME/.local/bin}"

# Refuse if a zellij session is alive
if pgrep -x zellij >/dev/null 2>&1; then
    echo "ERROR: zellij is still running. Kill all sessions first:"
    echo "  pkill -x zellij  (or zellij kill-all-sessions && zellij delete-all-sessions)"
    exit 1
fi

# Detect platform
case "$(uname -s)-$(uname -m)" in
    Linux-x86_64)  ASSET="zellij-x86_64-unknown-linux-musl.tar.gz" ;;
    Linux-aarch64) ASSET="zellij-aarch64-unknown-linux-musl.tar.gz" ;;
    Darwin-arm64)  ASSET="zellij-aarch64-apple-darwin.tar.gz" ;;
    Darwin-x86_64) ASSET="zellij-x86_64-apple-darwin.tar.gz" ;;
    *) echo "ERROR: unsupported platform $(uname -s)-$(uname -m)"; exit 1 ;;
esac

URL="https://github.com/zellij-org/zellij/releases/download/${VERSION}/${ASSET}"
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT

echo "Downloading $URL ..."
curl -fSL "$URL" -o "$TMP/zellij.tar.gz"

echo "Extracting ..."
tar -xzf "$TMP/zellij.tar.gz" -C "$TMP"

mkdir -p "$TARGET_DIR"
install -m 0755 "$TMP/zellij" "$TARGET_DIR/zellij"

echo "Installed: $($TARGET_DIR/zellij --version)"
echo "Path: $TARGET_DIR/zellij"

# If a system zellij is shadowing this, warn the user
if SYS_ZELLIJ=$(command -v zellij 2>/dev/null) && [ "$SYS_ZELLIJ" != "$TARGET_DIR/zellij" ]; then
    echo
    echo "WARNING: 'which zellij' resolves to $SYS_ZELLIJ — that one will run instead."
    echo "Either:"
    echo "  - prepend $TARGET_DIR to PATH in your shell rc, OR"
    echo "  - replace the system binary:  sudo install -m 0755 $TMP/zellij $SYS_ZELLIJ"
fi
