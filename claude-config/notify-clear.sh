#!/bin/bash
# Clear Claude Code notification for this pane
# Called by statusline-custom.sh when pane is viewed
# Also updates pane title to current repo:branch

[[ -z "$ZELLIJ" ]] && exit 0

# Remove notification file
rm -f "/tmp/zellij-notify-$ZELLIJ_PANE_ID" 2>/dev/null

# Update pane title to current repo:branch (removes bell, updates branch)
cwd=$(pwd)
repo=$(basename "$(git -C "$cwd" rev-parse --show-toplevel 2>/dev/null)" 2>/dev/null)
branch=$(git -C "$cwd" branch --show-current 2>/dev/null)

if [[ -n "$repo" && -n "$branch" ]]; then
    title="${repo}:${branch}"
elif [[ -n "$repo" ]]; then
    title="$repo"
else
    title="${cwd##*/}"
fi

# Rename pane to current repo:branch
zellij action rename-pane -p "$ZELLIJ_PANE_ID" "$title" 2>/dev/null

# Clear tab rename (remove bell)
zellij action undo-rename-tab 2>/dev/null

exit 0
