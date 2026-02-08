#!/bin/bash
# Unified stacked pane manager for Zellij
# Opens stacked panes for agent transcripts or background shell output
#
# Usage:
#   stacked-pane.sh --type agent   (called by PostToolUse hook for Task)
#   stacked-pane.sh --type shell   (called by PostToolUse hook for Bash)

[[ -z "$ZELLIJ" ]] && exit 0

PARENT_PANE_ID="$ZELLIJ_PANE_ID"
[[ -z "$PARENT_PANE_ID" ]] && exit 0

# Unified log directory
LOG_DIR="${HOME}/.cache/claude-dotfiles/logs"
debug_log() {
    if [[ -n "$CLAUDE_DOTFILES_DEBUG" ]]; then
        mkdir -p "$LOG_DIR" 2>/dev/null
        echo "[$(date)] [stacked-pane] $*" >> "$LOG_DIR/pane.log"
    fi
}

# Parse script arguments
PANE_TYPE=""
while [[ $# -gt 0 ]]; do
    case $1 in
        --type) PANE_TYPE="$2"; shift 2 ;;
        *) shift ;;
    esac
done

[[ -z "$PANE_TYPE" ]] && exit 0

# Read hook input from stdin
input=$(cat)

# ─── Parse hook input based on type ─────────────────────────────────────────

if [[ "$PANE_TYPE" == "agent" ]]; then
    # Extract agent ID and project path
    IFS=$'\t' read -r ITEM_ID PROJECT_DIR <<< "$(echo "$input" | python3 -c "
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

    [[ -z "$ITEM_ID" ]] && exit 0

    # Build transcript path
    TARGET_FILE="$HOME/.claude/projects/$PROJECT_DIR/agent-$ITEM_ID.jsonl"
    PANE_NAME="Agent $ITEM_ID"
    MAX_IDLE=10
    MAX_RUNTIME=600

elif [[ "$PANE_TYPE" == "shell" ]]; then
    # Extract task info
    IFS=$'\t' read -r IS_BACKGROUND ITEM_ID PROJECT_DIR CWD <<< "$(echo "$input" | python3 -c "
import sys, json, re

try:
    d = json.load(sys.stdin)
    tool_input = d.get('tool_input', {})
    is_background = tool_input.get('run_in_background', False)
    if not is_background:
        print('false\t\t\t')
        sys.exit(0)
    tool_response = d.get('tool_response', {})
    task_id = ''
    if isinstance(tool_response, dict):
        task_id = tool_response.get('backgroundTaskId', '')
        if not task_id:
            task_id = tool_response.get('task_id', '')
        if not task_id:
            task_id = tool_response.get('taskId', '')
    cwd = d.get('cwd', '.')
    project_dir = '-' + re.sub(r'/', '-', cwd.lstrip('/'))
    print('true', task_id, project_dir, cwd, sep='\t')
except:
    print('false\t\t\t')
" 2>/dev/null)"

    [[ "$IS_BACKGROUND" != "true" ]] && exit 0
    [[ -z "$ITEM_ID" ]] && exit 0

    # Build output path
    TARGET_FILE="/tmp/claude/$PROJECT_DIR/tasks/$ITEM_ID.output"
    PANE_NAME="Shell $ITEM_ID"
    MAX_IDLE=10
    MAX_RUNTIME=300

else
    exit 0
fi

debug_log "type=$PANE_TYPE id=$ITEM_ID file=$TARGET_FILE"

# ─── Wait for target file to appear ─────────────────────────────────────────

MAX_WAIT=$( [[ "$PANE_TYPE" == "shell" ]] && echo 10 || echo 5 )
for _i in $(seq 1 "$MAX_WAIT"); do
    [[ -f "$TARGET_FILE" ]] && break
    sleep 0.2
done

[[ ! -f "$TARGET_FILE" ]] && exit 0

# ─── Capture focus before creating pane ──────────────────────────────────────

FOCUSED_BEFORE=$(zellij action dump-layout 2>/dev/null | grep -o 'focused: true' -B 20 | grep -o 'pane_id: [^,]*' | head -1 | awk '{print $2}')

# ─── Build inner command based on type ───────────────────────────────────────

if [[ "$PANE_TYPE" == "agent" ]]; then
    INNER_CMD="
    echo -e '\033[0;36m$PANE_NAME\033[0m'
    echo '─────────────────────────────'

    TARGET_FILE='$TARGET_FILE'

    tail -f \"\$TARGET_FILE\" 2>/dev/null | while IFS= read -r line; do
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
    "
    COMPLETION_MSG="Agent completed"
    TIMEOUT_MSG="Timeout reached"
    REMOVED_MSG="Transcript removed"
else
    INNER_CMD="
    echo -e '\033[0;33m$PANE_NAME\033[0m'
    echo '─────────────────────────────'

    TARGET_FILE='$TARGET_FILE'

    # Wait for output file to exist (max 30 seconds)
    wait_count=0
    while [[ ! -f \"\$TARGET_FILE\" ]] && [[ \$wait_count -lt 30 ]]; do
        sleep 1
        ((wait_count++))
    done

    if [[ ! -f \"\$TARGET_FILE\" ]]; then
        echo -e '\033[0;31m✗ Output file not found\033[0m'
        exit 1
    fi

    tail -f \"\$TARGET_FILE\" 2>/dev/null &
    TAIL_PID=\$!
    "
    COMPLETION_MSG="Shell completed"
    TIMEOUT_MSG="Timeout reached"
    REMOVED_MSG="Output file removed"
fi

# ─── Shared monitoring loop ──────────────────────────────────────────────────

MONITOR_LOOP="
    last_mtime=0
    idle_count=0
    max_idle=$MAX_IDLE
    total_runtime=0
    max_runtime=$MAX_RUNTIME

    while kill -0 \$TAIL_PID 2>/dev/null; do
        ((total_runtime++))
        if [[ \$total_runtime -ge \$max_runtime ]]; then
            echo -e '\n\033[0;33m⏱ $TIMEOUT_MSG\033[0m'
            kill \$TAIL_PID 2>/dev/null
            exit 0
        fi

        if [[ -f \"\$TARGET_FILE\" ]]; then
            current_mtime=\$(stat -c%Y \"\$TARGET_FILE\" 2>/dev/null || echo 0)
            if [[ \$current_mtime -gt \$last_mtime ]]; then
                last_mtime=\$current_mtime
                idle_count=0
            else
                ((idle_count++))
                if [[ \$idle_count -ge \$max_idle ]]; then
                    echo -e '\n\033[0;32m✓ $COMPLETION_MSG\033[0m'
                    kill \$TAIL_PID 2>/dev/null
                    exit 0
                fi
            fi
        else
            echo -e '\n\033[0;31m✗ $REMOVED_MSG\033[0m'
            kill \$TAIL_PID 2>/dev/null
            exit 0
        fi
        sleep 1
    done
"

# ─── Create stacked pane ────────────────────────────────────────────────────

zellij run --stacked --stack-with "terminal_$PARENT_PANE_ID" --close-on-exit --name "$PANE_NAME" \
    -- bash -c "$INNER_CMD $MONITOR_LOOP" 2>/dev/null

# ─── Restore focus ───────────────────────────────────────────────────────────

sleep 0.3

FOCUSED_AFTER=$(zellij action dump-layout 2>/dev/null | grep -o 'focused: true' -B 20 | grep -o 'pane_id: [^,]*' | head -1 | awk '{print $2}')

if [[ -n "$FOCUSED_BEFORE" ]] && [[ "$FOCUSED_AFTER" != "$FOCUSED_BEFORE" ]]; then
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

exit 0
