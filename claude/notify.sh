#!/bin/bash
# Notification for Claude Code hooks
# - Stores pending pane rename (applied by precmd when pane is focused)
# - Plays audio notification immediately
# - Cleared by precmd when user interacts with shell

[[ -z "$ZELLIJ" ]] && exit 0

# Read hook input from stdin (contains cwd from Claude Code)
input=$(cat)
cwd=$(echo "$input" | python3 -c "import sys,json; print(json.load(sys.stdin).get('cwd','.'))" 2>/dev/null || echo ".")

# Build title: 🔔 repo:branch (or just directory name)
# Use cwd from hook input to get the correct pane's repo, not the focused pane's
repo=$(basename "$(git -C "$cwd" rev-parse --show-toplevel 2>/dev/null)" 2>/dev/null)
branch=$(git -C "$cwd" branch --show-current 2>/dev/null)
if [[ -n "$repo" && -n "$branch" ]]; then
    title="🔔 ${repo}:${branch}"
elif [[ -n "$repo" ]]; then
    title="🔔 $repo"
else
    title="🔔 ${cwd##*/}"
fi

# Store notification for this specific pane
# Can't rename specific pane - zellij action rename-pane only targets focused pane
NOTIFY_FILE="/tmp/zellij-notify-$ZELLIJ_PANE_ID"
echo "$title" > "$NOTIFY_FILE"

# Visual indicator: Add bell to tab name (visible even when pane not focused)
# Get current tab name, prepend bell if not already there
current_tab=$(zellij action dump-layout 2>/dev/null | grep -o 'tab name="[^"]*"' | head -1 | sed 's/tab name="//;s/"//')
if [[ -n "$current_tab" && "$current_tab" != 🔔* ]]; then
    zellij action rename-tab "🔔 $current_tab" 2>/dev/null
fi

# Audio notification (platform-specific)
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
