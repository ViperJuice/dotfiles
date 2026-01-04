#!/bin/bash
# Opens Zellij stacked panes for background shell output
# Called by PostToolUse hook when Bash tool is used with run_in_background
# Creates a pane stacked behind the parent Claude pane showing shell output

[[ -z "$ZELLIJ" ]] && exit 0

# Save the parent pane ID (the Claude pane that spawned the shell)
PARENT_PANE_ID="$ZELLIJ_PANE_ID"
[[ -z "$PARENT_PANE_ID" ]] && exit 0

# Read hook input from stdin
input=$(cat)

# Extract task info from hook input
eval $(echo "$input" | python3 -c "
import sys, json, re, shlex

try:
    d = json.load(sys.stdin)

    # Check if this is a background shell
    tool_input = d.get('tool_input', {})
    is_background = tool_input.get('run_in_background', False)

    if not is_background:
        print('IS_BACKGROUND=false')
        sys.exit(0)

    print('IS_BACKGROUND=true')

    # Get task ID from tool_response.backgroundTaskId
    tool_response = d.get('tool_response', {})
    task_id = ''

    if isinstance(tool_response, dict):
        # Primary: backgroundTaskId (actual field name from Claude)
        task_id = tool_response.get('backgroundTaskId', '')
        # Fallbacks
        if not task_id:
            task_id = tool_response.get('task_id', '')
        if not task_id:
            task_id = tool_response.get('taskId', '')

    # Get cwd for building output path
    cwd = d.get('cwd', '.')

    # Convert to Claude project format: /home/jenner/code/foo -> -home-jenner-code-foo
    project_dir = '-' + re.sub(r'/', '-', cwd.lstrip('/'))

    print(f'TASK_ID={shlex.quote(task_id)}')
    print(f'PROJECT_DIR={shlex.quote(project_dir)}')
    print(f'CWD={shlex.quote(cwd)}')
except Exception as e:
    print('IS_BACKGROUND=false')
" 2>/dev/null)

# Only proceed if this is a background shell with a task ID
[[ "$IS_BACKGROUND" != "true" ]] && exit 0
[[ -z "$TASK_ID" ]] && exit 0

# Build output path
OUTPUT_FILE="/tmp/claude/$PROJECT_DIR/tasks/$TASK_ID.output"

# Check if output file exists (may take a moment to be created)
for i in {1..10}; do
    [[ -f "$OUTPUT_FILE" ]] && break
    sleep 0.2
done

[[ ! -f "$OUTPUT_FILE" ]] && exit 0

# Capture currently focused pane BEFORE creating output pane
# This lets us detect if user switches panes during hook execution
FOCUSED_BEFORE=$(zellij action dump-layout 2>/dev/null | grep -o 'focused: true' -B 20 | grep -o 'pane_id: [^,]*' | head -1 | awk '{print $2}')

# Create a stacked pane showing the shell output, stacked with the parent pane
zellij run --stacked --stack-with "terminal_$PARENT_PANE_ID" --close-on-exit --name "Shell $TASK_ID" \
    -- bash -c "
    echo -e '\033[0;33mBackground Shell $TASK_ID\033[0m'
    echo '─────────────────────────────'

    OUTPUT_FILE='$OUTPUT_FILE'

    # Wait for output file to exist (max 30 seconds)
    wait_count=0
    while [[ ! -f \"\$OUTPUT_FILE\" ]] && [[ \$wait_count -lt 30 ]]; do
        sleep 1
        ((wait_count++))
    done

    if [[ ! -f \"\$OUTPUT_FILE\" ]]; then
        echo -e '\033[0;31m✗ Output file not found\033[0m'
        exit 1
    fi

    # Use tail -f in background, monitor file mtime to detect completion
    tail -f \"\$OUTPUT_FILE\" 2>/dev/null &
    TAIL_PID=\$!

    # Monitor file modification time - exit when file stops being updated
    last_mtime=0
    idle_count=0
    max_idle=10
    total_runtime=0
    max_runtime=300  # 5 minute maximum

    while kill -0 \$TAIL_PID 2>/dev/null; do
        ((total_runtime++))
        if [[ \$total_runtime -ge \$max_runtime ]]; then
            echo -e '\n\033[0;33m⏱ Timeout reached\033[0m'
            kill \$TAIL_PID 2>/dev/null
            exit 0
        fi

        if [[ -f \"\$OUTPUT_FILE\" ]]; then
            current_mtime=\$(stat -c%Y \"\$OUTPUT_FILE\" 2>/dev/null || echo 0)
            if [[ \$current_mtime -gt \$last_mtime ]]; then
                last_mtime=\$current_mtime
                idle_count=0
            else
                ((idle_count++))
                if [[ \$idle_count -ge \$max_idle ]]; then
                    echo -e '\n\033[0;32m✓ Shell completed\033[0m'
                    kill \$TAIL_PID 2>/dev/null
                    exit 0
                fi
            fi
        else
            # File was deleted - exit
            echo -e '\n\033[0;31m✗ Output file removed\033[0m'
            kill \$TAIL_PID 2>/dev/null
            exit 0
        fi
        sleep 1
    done
" 2>/dev/null

# Focus back to the parent pane so the shell pane goes behind in the stack
# BUT ONLY if user hasn't switched to another pane (don't steal focus!)
DEBUG_LOG="/tmp/zellij-bash-pane-debug.log"

# Wait for pane creation to complete
sleep 0.3

# Check if user has switched panes since we started
FOCUSED_AFTER=$(zellij action dump-layout 2>/dev/null | grep -o 'focused: true' -B 20 | grep -o 'pane_id: [^,]*' | head -1 | awk '{print $2}')

# Only restore focus if Zellij changed it (don't steal focus from user's active work)
if [[ -n "$FOCUSED_BEFORE" ]] && [[ "$FOCUSED_AFTER" != "$FOCUSED_BEFORE" ]]; then
    # Zellij changed focus - restore to where user was
    if zellij action focus-pane-by-id "$FOCUSED_BEFORE" 2>>"$DEBUG_LOG"; then
        echo "[$(date)] Restored focus to $FOCUSED_BEFORE (was $FOCUSED_AFTER)" >> "$DEBUG_LOG"
    else
        echo "[$(date)] WARN: focus-pane-by-id failed, retrying" >> "$DEBUG_LOG"
        sleep 0.2
        if ! zellij action focus-pane-by-id "$FOCUSED_BEFORE" 2>>"$DEBUG_LOG"; then
            echo "[$(date)] ERROR: Could not restore focus to $FOCUSED_BEFORE" >> "$DEBUG_LOG"
            zellij action focus-previous-pane 2>>"$DEBUG_LOG"
        fi
    fi
else
    # Focus unchanged - don't touch it
    echo "[$(date)] Focus unchanged at $FOCUSED_AFTER - no action needed" >> "$DEBUG_LOG"
fi

# Exit immediately so hook doesn't block
exit 0
