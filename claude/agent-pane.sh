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

# Extract agent ID and project path from hook input
eval $(echo "$input" | python3 -c "
import sys, json, re, shlex

try:
    d = json.load(sys.stdin)

    # Get agent ID from tool_response (PostToolUse provides this)
    tool_response = d.get('tool_response', {})
    agent_id = ''

    # Check for agentId in tool_response
    if isinstance(tool_response, dict):
        agent_id = tool_response.get('agentId', '')

    # Get cwd for project path
    cwd = d.get('cwd', '.')

    # Convert to Claude project format: /home/jenner/code/foo -> -home-jenner-code-foo
    project_dir = '-' + re.sub(r'/', '-', cwd.lstrip('/'))

    print(f'AGENT_ID={shlex.quote(agent_id)}')
    print(f'PROJECT_DIR={shlex.quote(project_dir)}')
except Exception as e:
    print('AGENT_ID=\"\"')
    print('PROJECT_DIR=\"\"')
" 2>/dev/null)

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

# Run pane creation in background to avoid blocking the hook
{
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

        while kill -0 \$TAIL_PID 2>/dev/null; do
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
            fi
            sleep 1
        done
    " 2>/dev/null

    # Focus back to the parent pane so the agent pane goes behind in the stack
    # (requires our forked zellij with focus-pane-by-id support)
    sleep 0.1
    zellij action focus-pane-by-id "terminal_$PARENT_PANE_ID" 2>/dev/null
} &

# Exit immediately so hook doesn't block
exit 0
