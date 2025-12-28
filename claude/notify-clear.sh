#!/bin/bash
# Clear Claude Code notification for this pane
# Called by UserPromptSubmit hook when user submits a prompt

[[ -z "$ZELLIJ" ]] && exit 0

# Remove pending notification file
rm -f "/tmp/zellij-notify-$ZELLIJ_PANE_ID" 2>/dev/null

# Clear pane and tab name modifications
zellij action undo-rename-pane 2>/dev/null
zellij action undo-rename-tab 2>/dev/null

exit 0
