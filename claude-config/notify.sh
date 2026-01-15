#!/bin/bash
# Notification for Claude Code hooks
# - Renames pane with bell icon (using --pane-id to target correct pane)
# - Renames tab with bell icon (always visible)
# - Plays audio notification
#
# NOTE: Requires Zellij with --pane-id support (PR #4570)
# https://github.com/zellij-org/zellij/pull/4570

[[ -z "$ZELLIJ" ]] && exit 0

# Read hook input from stdin (contains cwd from Claude Code)
input=$(cat)

# Debug: log notifications to help trace unexpected beeps
{
    printf '%s pane=%s zellij=%s\n' "$(date '+%Y-%m-%d %H:%M:%S')" "${ZELLIJ_PANE_ID:-}" "${ZELLIJ:-}"
    printf 'input=%s\n' "$input"
    echo '---'
} >> /tmp/claude-notify.log
read_meta=$(python3 -c "import sys,json; d=json.load(sys.stdin); print(d.get('cwd','.'), d.get('permission_mode',''), d.get('session_id',''), sep='\\t')" 2>/dev/null <<<"$input" || echo ".\t\t")
cwd=$(echo "$read_meta" | awk -F '\t' '{print $1}')
permission_mode=$(echo "$read_meta" | awk -F '\t' '{print $2}')
session_id=$(echo "$read_meta" | awk -F '\t' '{print $3}')

# Build title: 🔔 repo:branch (or just directory name)
repo=$(basename "$(git -C "$cwd" rev-parse --show-toplevel 2>/dev/null)" 2>/dev/null)
branch=$(git -C "$cwd" branch --show-current 2>/dev/null)
if [[ -n "$repo" && -n "$branch" ]]; then
    title="🔔 ${repo}:${branch}"
elif [[ -n "$repo" ]]; then
    title="🔔 $repo"
else
    title="🔔 ${cwd##*/}"
fi

# Store notification for this pane (for clearing later)
state_dir="${XDG_CACHE_HOME:-$HOME/.cache}/claude-notify"
mkdir -p "$state_dir" 2>/dev/null
notify_file="$state_dir/zellij-notify-$ZELLIJ_PANE_ID"
already_notified=0
if [[ -f "$notify_file" ]]; then
    already_notified=1
fi
echo "$title" > "$notify_file"

# Debug: track notify state
{
    printf '%s notify_file=%s exists=%s\n' "$(date '+%Y-%m-%d %H:%M:%S')" "$notify_file" "$already_notified"
    echo '---'
} >> /tmp/claude-notify.log

# Rename this specific pane by ID
zellij action rename-pane -p "$ZELLIJ_PANE_ID" "$title" 2>/dev/null

# Visual indicator: Add bell to tab name (always visible)
# Get current tab name, prepend bell if not already there
current_tab=$(zellij action dump-layout 2>/dev/null | grep -o 'tab name="[^"]*"' | head -1 | sed 's/tab name="//;s/"//')
if [[ -n "$current_tab" && "$current_tab" != 🔔* ]]; then
    zellij action rename-tab "🔔 $current_tab" 2>/dev/null
fi

# Audio notification (platform-specific), only once until cleared.
# Skip automated sessions that run with bypassPermissions.
if [[ "$already_notified" -eq 0 && "$permission_mode" != "bypassPermissions" ]]; then
    if command -v powershell.exe &>/dev/null; then
        # WSL: PowerShell beep
        powershell.exe -NoProfile -Command '[console]::beep(800,200)' &>/dev/null &
    elif [[ "$(uname)" == "Darwin" ]] && command -v afplay &>/dev/null; then
        # macOS: System sound
        afplay /System/Library/Sounds/Ping.aiff &>/dev/null &
    elif command -v paplay &>/dev/null; then
        # Linux: PulseAudio (if sound file exists)
        for snd in /usr/share/sounds/freedesktop/stereo/bell.oga /usr/share/sounds/freedesktop/stereo/complete.oga; do
            if [ -f "$snd" ]; then
                paplay "$snd" &>/dev/null &
                break
            fi
        done
    fi
fi
