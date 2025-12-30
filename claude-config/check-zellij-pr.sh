#!/bin/bash
# Check if Zellij PR #4570 has been merged
# Run via cron: 0 9 * * * /home/jenner/code/dotfiles/claude/check-zellij-pr.sh

PR_URL="https://github.com/zellij-org/zellij/pull/4570"
MARKER_FILE="/tmp/zellij-pr-4570-notified"

# Don't notify more than once
[[ -f "$MARKER_FILE" ]] && exit 0

# Check PR status
status=$(gh pr view 4570 --repo zellij-org/zellij --json state --jq '.state' 2>/dev/null)

if [[ "$status" == "MERGED" ]]; then
    # Create marker so we don't notify again
    touch "$MARKER_FILE"

    # Desktop notification (works on most Linux/WSL)
    if command -v notify-send &>/dev/null; then
        notify-send "Zellij PR Merged!" "PR #4570 was merged. You can update Zellij and remove the custom build." --urgency=normal
    fi

    # Also beep
    if command -v powershell.exe &>/dev/null; then
        powershell.exe -NoProfile -Command '[console]::beep(600,300);[console]::beep(800,300);[console]::beep(1000,300)' &>/dev/null
    fi

    # Log it
    echo "$(date): Zellij PR #4570 has been MERGED! Update zellij and remove custom build." >> ~/zellij-pr-merged.log
    echo ""
    echo "=== ZELLIJ PR #4570 MERGED ==="
    echo "Run: sudo apt update && sudo apt upgrade zellij"
    echo "Or:  brew upgrade zellij"
    echo "Then remove: /usr/local/bin/zellij (custom build)"
    echo "=============================="
fi
