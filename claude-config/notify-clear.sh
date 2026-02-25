#!/bin/bash
# Clear Claude Code notification for this pane
# Called by UserPromptSubmit hook when user submits a prompt
# Restores original pane/tab titles

[[ -z "$ZELLIJ" ]] && exit 0

# Unified log directory
LOG_DIR="${HOME}/.cache/claude-dotfiles/logs"
debug_log() {
    if [[ -n "$CLAUDE_DOTFILES_DEBUG" ]]; then
        mkdir -p "$LOG_DIR" 2>/dev/null
        echo "[$(date '+%H:%M:%S')] [notify-clear] $*" >> "$LOG_DIR/notify.log"
    fi
}

state_dir="${XDG_CACHE_HOME:-$HOME/.cache}/claude-notify"
notify_file="$state_dir/zellij-notify-${ZELLIJ_SESSION_NAME:-default}-$ZELLIJ_PANE_ID"

debug_log "pane=$ZELLIJ_PANE_ID clearing=$notify_file"

# Restore original tab name from saved state (instead of undo-rename-tab)
if [[ -f "$notify_file.tab" ]]; then
    original_tab=$(cat "$notify_file.tab")
    if [[ -n "$original_tab" ]]; then
        zellij action rename-tab "$original_tab" 2>/dev/null
    else
        zellij action undo-rename-tab 2>/dev/null
    fi
    rm -f "$notify_file.tab" 2>/dev/null
else
    # Fallback: undo-rename-tab if no saved state
    zellij action undo-rename-tab 2>/dev/null
fi

# Remove notification files
rm -f "$notify_file" 2>/dev/null

# Use session root (set at launch), not transient cwd
session_root_file="${XDG_CACHE_HOME:-$HOME/.cache}/claude-dotfiles/pane-session/$ZELLIJ_PANE_ID"
session_root=$(cat "$session_root_file" 2>/dev/null)
session_root="${session_root:-$(pwd)}"  # fallback

# Update pane title to current repo:branch (removes bell, updates branch)
repo=$(basename "$(git -C "$session_root" rev-parse --show-toplevel 2>/dev/null)" 2>/dev/null)
branch=$(git -C "$session_root" branch --show-current 2>/dev/null)

if [[ -n "$repo" && -n "$branch" ]]; then
    title="${repo}:${branch}"
elif [[ -n "$repo" ]]; then
    title="$repo"
else
    title="${session_root##*/}"
fi

zellij action rename-pane -p "$ZELLIJ_PANE_ID" "$title" 2>/dev/null

# Clean up orphaned notifications older than 4 hours for ANY pane in this session
find "$state_dir" -name "zellij-notify-${ZELLIJ_SESSION_NAME:-default}-*" -mmin +240 -delete 2>/dev/null

exit 0
