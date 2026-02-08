#!/bin/bash
# Opens Zellij stacked panes for agent transcripts
# Called by PostToolUse hook when Task tool is used
# Creates a pane stacked behind the parent Claude pane showing agent output

[[ -z "$ZELLIJ" ]] && exit 0

# Save the parent pane ID (the Claude pane that spawned the agent)
PARENT_PANE_ID="$ZELLIJ_PANE_ID"
[[ -z "$PARENT_PANE_ID" ]] && exit 0

# Read hook input from stdin
input=$(cat)

# Extract agent ID and project path from hook input (stdin piping, no eval)
IFS=$'\t' read -r AGENT_ID PROJECT_DIR <<< "$(echo "$input" | python3 -c "
import sys, json, re

try:
    d = json.load(sys.stdin)

    tool_response = d.get('tool_response', {})
    agent_id = ''
    if isinstance(tool_response, dict):
        agent_id = tool_response.get('agentId', '')

    cwd = d.get('cwd', '.')
    project_dir = '-' + re.sub(r'/', '-', cwd.lstrip('/'))

    print(agent_id, project_dir, sep='\t')
except:
    print('\t')
" 2>/dev/null)"

# Only proceed if we have an agent ID
[[ -z "$AGENT_ID" ]] && exit 0

# Build transcript path
TRANSCRIPT="$HOME/.claude/projects/$PROJECT_DIR/agent-$AGENT_ID.jsonl"

# Check if transcript exists (may take a moment to be created)
for i in {1..5}; do
    [[ -f "$TRANSCRIPT" ]] && break
    sleep 0.2
done

[[ ! -f "$TRANSCRIPT" ]] && exit 0

# Capture currently focused pane BEFORE creating output pane
# This lets us detect if user switches panes during hook execution
FOCUSED_BEFORE=$(zellij action dump-layout 2>/dev/null | grep -o 'focused: true' -B 20 | grep -o 'pane_id: [^,]*' | head -1 | awk '{print $2}')

# Create a stacked pane showing the agent log, stacked with the parent pane
# Use terminal_N format for pane ID
zellij run --stacked --stack-with "terminal_$PARENT_PANE_ID" --close-on-exit --name "Agent $AGENT_ID" \
    -- bash -c "
    echo -e '\033[0;36mAgent $AGENT_ID\033[0m'
    echo '─────────────────────────────'

    TRANSCRIPT='$TRANSCRIPT'

    # Use tail -f in background, monitor file mtime to detect completion
    tail -f \"\$TRANSCRIPT\" 2>/dev/null | while IFS= read -r line; do
        echo \"\$line\" | python3 -c '
import sys, json
try:
    d = json.loads(sys.stdin.read())
    msg = d.get(\"message\", {})
    content = msg.get(\"content\", [])
    if isinstance(content, list):
        for c in content:
            if isinstance(c, dict) and c.get(\"type\") == \"text\":
                text = c.get(\"text\", \"\")[:500]
                if text: print(text)
            elif isinstance(c, dict) and c.get(\"type\") == \"tool_use\":
                print(f\"[{c.get(\"name\", \"\")}]\")
except:
    pass
' 2>/dev/null
    done &
    TAIL_PID=\$!

    # Monitor file modification time - exit when file stops being updated
    last_mtime=0
    idle_count=0
    max_idle=10
    total_runtime=0
    max_runtime=600  # 10 minute maximum for agents

    while kill -0 \$TAIL_PID 2>/dev/null; do
        ((total_runtime++))
        if [[ \$total_runtime -ge \$max_runtime ]]; then
            echo -e '\n\033[0;33m⏱ Timeout reached\033[0m'
            kill \$TAIL_PID 2>/dev/null
            exit 0
        fi

        if [[ -f \"\$TRANSCRIPT\" ]]; then
            current_mtime=\$(stat -c%Y \"\$TRANSCRIPT\" 2>/dev/null || echo 0)
            if [[ \$current_mtime -gt \$last_mtime ]]; then
                last_mtime=\$current_mtime
                idle_count=0
            else
                ((idle_count++))
                if [[ \$idle_count -ge \$max_idle ]]; then
                    echo -e '\n\033[0;32m✓ Agent completed\033[0m'
                    kill \$TAIL_PID 2>/dev/null
                    exit 0
                fi
            fi
        else
            # Transcript file was deleted - exit
            echo -e '\n\033[0;31m✗ Transcript removed\033[0m'
            kill \$TAIL_PID 2>/dev/null
            exit 0
        fi
        sleep 1
    done
" 2>/dev/null

# Focus back to the parent pane so the agent pane goes behind in the stack
# BUT ONLY if user hasn't switched to another pane (don't steal focus!)
LOG_DIR="${HOME}/.cache/claude-dotfiles/logs"
debug_log() {
    if [[ -n "$CLAUDE_DOTFILES_DEBUG" ]]; then
        mkdir -p "$LOG_DIR" 2>/dev/null
        echo "[$(date)] $*" >> "$LOG_DIR/pane.log"
    fi
}

# Wait for pane creation to complete
sleep 0.3

# Check if user has switched panes since we started
FOCUSED_AFTER=$(zellij action dump-layout 2>/dev/null | grep -o 'focused: true' -B 20 | grep -o 'pane_id: [^,]*' | head -1 | awk '{print $2}')

# Only restore focus if Zellij changed it (don't steal focus from user's active work)
if [[ -n "$FOCUSED_BEFORE" ]] && [[ "$FOCUSED_AFTER" != "$FOCUSED_BEFORE" ]]; then
    # Zellij changed focus - restore to where user was
    if zellij action focus-pane-by-id "$FOCUSED_BEFORE" 2>/dev/null; then
        debug_log "Restored focus to $FOCUSED_BEFORE (was $FOCUSED_AFTER)"
    else
        debug_log "WARN: focus-pane-by-id failed, retrying"
        sleep 0.2
        if ! zellij action focus-pane-by-id "$FOCUSED_BEFORE" 2>/dev/null; then
            debug_log "ERROR: Could not restore focus to $FOCUSED_BEFORE"
            zellij action focus-previous-pane 2>/dev/null
        fi
    fi
else
    debug_log "Focus unchanged at $FOCUSED_AFTER - no action needed"
fi

# Exit immediately so hook doesn't block
exit 0
