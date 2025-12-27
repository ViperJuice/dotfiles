#!/bin/bash
# Notification for Claude Code hooks
# - Beep sound via PowerShell (works from background processes)
# - BEL character for tab asterisk indicator

if command -v powershell.exe &>/dev/null; then
    # Play a beep sound (800Hz for 200ms)
    powershell.exe -NoProfile -Command "[console]::beep(800,200)" &>/dev/null &
fi

# Send BEL for tab indicator (may work depending on context)
printf "\a" 2>/dev/null || true
