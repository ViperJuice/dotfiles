#!/bin/bash
# Notification for Claude Code hooks
# - Renames pane with bell emoji prepended to repo:branch
# - Plays audio notification
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

# Visual: Rename pane
zellij action rename-pane "$title"

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
