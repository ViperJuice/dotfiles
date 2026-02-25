#!/bin/bash
# Notification for Claude Code hooks
# - Renames pane with bell icon (using --pane-id to target correct pane)
# - Renames tab with bell icon (always visible)
# - Plays audio notification
#
# NOTE: Requires Zellij with --pane-id support (custom fork)

[[ -z "$ZELLIJ" ]] && exit 0

# Read hook input from stdin (contains cwd from Claude Code)
input=$(cat)

# Unified log directory
LOG_DIR="${HOME}/.cache/claude-dotfiles/logs"
debug_log() {
    if [[ -n "$CLAUDE_DOTFILES_DEBUG" ]]; then
        mkdir -p "$LOG_DIR" 2>/dev/null
        echo "[$(date '+%H:%M:%S')] [notify] $*" >> "$LOG_DIR/notify.log"
    fi
}

# Parse metadata from hook input via stdin (no eval)
IFS=$'\t' read -r cwd permission_mode session_id <<< "$(python3 -c "
import sys, json
try:
    d = json.load(sys.stdin)
    print(d.get('cwd', '.'), d.get('permission_mode', ''), d.get('session_id', ''), sep='\t')
except:
    print('.\t\t')
" 2>/dev/null <<<"$input")"

debug_log "pane=$ZELLIJ_PANE_ID session=${ZELLIJ_SESSION_NAME:-} cwd=$cwd"

# Use session root (set at launch), not transient cwd
session_root_file="${XDG_CACHE_HOME:-$HOME/.cache}/claude-dotfiles/pane-session/$ZELLIJ_PANE_ID"
session_root=$(cat "$session_root_file" 2>/dev/null)
session_root="${session_root:-$cwd}"  # fallback to hook cwd

# Build title: repo:branch (or just directory name)
repo=$(basename "$(git -C "$session_root" rev-parse --show-toplevel 2>/dev/null)" 2>/dev/null)
branch=$(git -C "$session_root" branch --show-current 2>/dev/null)
if [[ -n "$repo" && -n "$branch" ]]; then
    title="${repo}:${branch}"
elif [[ -n "$repo" ]]; then
    title="$repo"
else
    title="${cwd##*/}"
fi

# Store notification for this pane (includes session ID for uniqueness)
state_dir="${XDG_CACHE_HOME:-$HOME/.cache}/claude-notify"
mkdir -p "$state_dir" 2>/dev/null

# Clean up stale notification files (older than 4 hours)
find "$state_dir" -name 'zellij-notify-*' -mmin +240 -delete 2>/dev/null

notify_file="$state_dir/zellij-notify-${ZELLIJ_SESSION_NAME:-default}-$ZELLIJ_PANE_ID"

# If there's an existing notification for THIS pane from a DIFFERENT cwd/session,
# clear it first (handles the "session ended, new session started" case)
if [[ -f "$notify_file" ]]; then
    old_title=$(cat "$notify_file" 2>/dev/null)
    if [[ "$old_title" != "$title" ]]; then
        # Different repo/branch — old notification is stale, clean it up
        rm -f "$notify_file" "$notify_file.tab" 2>/dev/null
        debug_log "cleared stale notification: was='$old_title' now='$title'"
    fi
fi

already_notified=0
if [[ -f "$notify_file" ]]; then
    already_notified=1
fi

# Save the original tab name so notify-clear can restore it
current_tab=$(zellij action dump-layout 2>/dev/null | grep -o 'tab name="[^"]*"' | head -1 | sed 's/tab name="//;s/"//')
echo "$title" > "$notify_file"
# Store original tab name for restore (separate file to avoid conflicts)
echo "$current_tab" > "$notify_file.tab"

debug_log "notify_file=$notify_file already=$already_notified tab=$current_tab"

# Rename this specific pane by ID with bell
zellij action rename-pane -p "$ZELLIJ_PANE_ID" "🔔 $title" 2>/dev/null

# Visual indicator: Add bell to tab name (always visible)
if [[ -n "$current_tab" && "$current_tab" != 🔔* ]]; then
    zellij action rename-tab "🔔 $current_tab" 2>/dev/null
fi

# Audio notification (platform-specific), only once until cleared.
# Skip automated sessions that run with bypassPermissions.
if [[ "$already_notified" -eq 0 && "$permission_mode" != "bypassPermissions" ]]; then
    if command -v powershell.exe &>/dev/null; then
        powershell.exe -NoProfile -Command '[console]::beep(800,200)' &>/dev/null &
    elif [[ "$(uname)" == "Darwin" ]] && command -v afplay &>/dev/null; then
        afplay /System/Library/Sounds/Ping.aiff &>/dev/null &
    elif command -v pw-play &>/dev/null || command -v paplay &>/dev/null || command -v aplay &>/dev/null; then
        for snd in /usr/share/sounds/freedesktop/stereo/bell.oga /usr/share/sounds/freedesktop/stereo/complete.oga; do
            if [ -f "$snd" ]; then
                if command -v pw-play &>/dev/null; then
                    pw-play "$snd" &>/dev/null &
                elif command -v paplay &>/dev/null; then
                    paplay "$snd" &>/dev/null &
                elif command -v aplay &>/dev/null; then
                    aplay "$snd" &>/dev/null &
                fi
                break
            fi
        done
    fi
fi
