#!/bin/bash
# Notification for Claude Code hooks
# - Renames pane with bell emoji prepended to repo:branch
# - Plays audio notification
# - Cleared by precmd when user interacts with shell

[[ -z "$ZELLIJ" ]] && exit 0

# Build title: 🔔 repo:branch (or just directory name)
repo=$(basename "$(git rev-parse --show-toplevel 2>/dev/null)" 2>/dev/null)
branch=$(git branch --show-current 2>/dev/null)
if [[ -n "$repo" && -n "$branch" ]]; then
    title="🔔 ${repo}:${branch}"
elif [[ -n "$repo" ]]; then
    title="🔔 $repo"
else
    title="🔔 ${PWD##*/}"
fi

# Visual: Rename pane
zellij action rename-pane "$title"

# Audio: PowerShell beep
if command -v powershell.exe &>/dev/null; then
    powershell.exe -NoProfile -Command '[console]::beep(800,200)' &>/dev/null &
fi
