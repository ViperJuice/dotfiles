#!/bin/bash
# Notification for Claude Code hooks
# - Renames pane with bell emoji prepended to repo:branch
# - Clears when pane is focused (persistent until acknowledged)
# - Plays audio notification

LOG="/tmp/claude-notify-debug.log"
echo "$(date '+%H:%M:%S') notify.sh called, ZELLIJ='$ZELLIJ', ZELLIJ_PANE_ID='$ZELLIJ_PANE_ID'" >> "$LOG"

[[ -z "$ZELLIJ" ]] && { echo "$(date '+%H:%M:%S') exiting - not in Zellij" >> "$LOG"; exit 0; }

MY_PANE="terminal_$ZELLIJ_PANE_ID"
echo "$(date '+%H:%M:%S') MY_PANE='$MY_PANE'" >> "$LOG"

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
echo "$(date '+%H:%M:%S') renaming pane to '$title'..." >> "$LOG"
zellij action rename-pane "$title" 2>> "$LOG" && echo "$(date '+%H:%M:%S') rename succeeded" >> "$LOG" || echo "$(date '+%H:%M:%S') rename failed" >> "$LOG"

# Audio: Use PowerShell beep (paplay needs sound-theme-freedesktop package)
if command -v powershell.exe &>/dev/null; then
    powershell.exe -NoProfile -Command '[console]::beep(800,200)' &>/dev/null &
elif command -v paplay &>/dev/null && [[ -f /usr/share/sounds/freedesktop/stereo/bell.oga ]]; then
    paplay /usr/share/sounds/freedesktop/stereo/bell.oga 2>/dev/null &
fi

# Focus watcher: clear when pane GAINS focus (was unfocused, then becomes focused)
(
  was_focused=true  # Assume focused initially, wait for unfocus then refocus
  while true; do
    sleep 1
    focused=$(zellij action list-clients 2>/dev/null | awk 'NR>1 {print $2}' | head -1)
    if [[ "$focused" == "$MY_PANE" ]]; then
      if [[ "$was_focused" == false ]]; then
        # Pane gained focus - clear notification
        echo "$(date '+%H:%M:%S') pane gained focus, clearing" >> "$LOG"
        zellij action undo-rename-pane 2>/dev/null
        exit 0
      fi
      was_focused=true
    else
      was_focused=false
    fi
  done
) &
disown
