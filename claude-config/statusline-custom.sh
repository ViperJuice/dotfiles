#!/bin/bash

# Auto-clear notification when pane is viewed
# If this statusline is being rendered, the user can see the pane
NOTIFY_FILE="/tmp/zellij-notify-$ZELLIJ_PANE_ID"
if [[ -n "$ZELLIJ_PANE_ID" && -f "$NOTIFY_FILE" ]]; then
    # Clear notification since user is looking at this pane
    ~/.claude/notify-clear.sh
fi

# Read JSON input from stdin
input=$(cat)

# Extract all values using Python
eval $(python3 -c "
import json, shlex, os, sys

try:
    d = json.loads('''$input''')

    # Debug: log input to file for troubleshooting
    with open('/tmp/statusline-debug.log', 'a') as f:
        f.write(json.dumps(d, indent=2) + '\n---\n')

    # Basic fields with multiple fallback paths
    model_obj = d.get('model', {})
    if isinstance(model_obj, dict):
        model = model_obj.get('display_name') or model_obj.get('name', '?')
    else:
        model = str(model_obj) if model_obj else '?'

    cwd = d.get('cwd') or d.get('workspace', {}).get('current_dir', '.')

    cost_obj = d.get('cost', {})
    cost = cost_obj.get('total_cost_usd', 0) if isinstance(cost_obj, dict) else 0

    transcript = d.get('transcript_path', '')

    # Context from current_usage (accurate) with fallback
    ctx = d.get('context_window', {})
    ctx_size = ctx.get('context_window_size', 200000) if isinstance(ctx, dict) else 200000
    current = ctx.get('current_usage') if isinstance(ctx, dict) else None

    if current and isinstance(current, dict):
        # Use current_usage: input + cache tokens
        tokens = (current.get('input_tokens', 0) +
                  current.get('cache_creation_input_tokens', 0) +
                  current.get('cache_read_input_tokens', 0))
    else:
        tokens = 0

    print(f'MODEL_DISPLAY={shlex.quote(str(model))}')
    print(f'CURRENT_DIR={shlex.quote(str(cwd))}')
    print(f'COST={float(cost):.2f}')
    print(f'TRANSCRIPT_PATH={shlex.quote(str(transcript))}')
    print(f'CONTEXT_SIZE={int(ctx_size)}')
    print(f'TOKENS_USED={int(tokens)}')
except Exception as e:
    # Log error for debugging
    with open('/tmp/statusline-debug.log', 'a') as f:
        f.write(f'ERROR: {e}\n')
    print('MODEL_DISPLAY=\"?\"')
    print('CURRENT_DIR=\".\"')
    print('COST=0.00')
    print('TRANSCRIPT_PATH=\"\"')
    print('CONTEXT_SIZE=200000')
    print('TOKENS_USED=0')
")

# Get repo name and branch, or show directory name
REPO_INFO=""
if [ -n "$CURRENT_DIR" ] && [ -d "$CURRENT_DIR" ]; then
    if git -C "$CURRENT_DIR" rev-parse --git-dir > /dev/null 2>&1; then
        REPO_NAME=$(basename "$(git -C "$CURRENT_DIR" rev-parse --show-toplevel 2>/dev/null)" 2>/dev/null)
        BRANCH=$(git -C "$CURRENT_DIR" --no-optional-locks rev-parse --abbrev-ref HEAD 2>/dev/null)
        REPO_INFO="📁 $REPO_NAME ($BRANCH)"
    else
        REPO_INFO="📂 $(basename "$CURRENT_DIR")"
    fi
else
    REPO_INFO="📂 ?"
fi

# Calculate context percentage of total window
PERCENT_USED=0
if [ "$CONTEXT_SIZE" -gt 0 ] 2>/dev/null && [ "$TOKENS_USED" -gt 0 ] 2>/dev/null; then
    PERCENT_USED=$((TOKENS_USED * 100 / CONTEXT_SIZE))
    if [ "$PERCENT_USED" -gt 100 ]; then
        PERCENT_USED=100
    fi
fi

# Build context bar (fills as context is used)
BAR_LENGTH=10
FILLED_CHARS=$((BAR_LENGTH * PERCENT_USED / 100))
if [ "$FILLED_CHARS" -gt 10 ]; then FILLED_CHARS=10; fi
EMPTY_CHARS=$((BAR_LENGTH - FILLED_CHARS))
CONTEXT_BAR="["
for i in $(seq 1 $FILLED_CHARS); do CONTEXT_BAR="${CONTEXT_BAR}█"; done
for i in $(seq 1 $EMPTY_CHARS); do CONTEXT_BAR="${CONTEXT_BAR}░"; done
CONTEXT_BAR="${CONTEXT_BAR}] ${PERCENT_USED}%"

# Track background processes from transcript
BACKGROUND_LINE=""
if [ -n "$TRANSCRIPT_PATH" ] && [ -f "$TRANSCRIPT_PATH" ]; then
    # Get project dir from transcript path for finding agent files
    PROJECT_DIR=$(dirname "$TRANSCRIPT_PATH")

    BACKGROUND_LINE=$(python3 -c "
import json
import os
import glob
import time
import re

transcript_path = '$TRANSCRIPT_PATH'
project_dir = '$PROJECT_DIR'
context_size = $CONTEXT_SIZE

# Track background processes
bg_shells = {}           # tool_id -> backgroundTaskId
async_agent_ids = set()  # agent_ids that are running (async launched)
completed_agent_ids = set()  # agent_ids that have been retrieved via TaskOutput
completed_shell_ids = set()  # backgroundTaskIds that have completed (from bash-notification)

try:
    with open(transcript_path, 'r') as f:
        for line in f:
            try:
                entry = json.loads(line)
                msg = entry.get('message', {})
                content = msg.get('content', [])

                if isinstance(content, list):
                    for block in content:
                        # Handle string content (user messages with bash-notification)
                        if isinstance(block, dict) and block.get('type') == 'text':
                            text = block.get('text', '')
                            # Parse <bash-notification> for completed shells
                            for match in re.finditer(r'<bash-notification>.*?<shell-id>([^<]+)</shell-id>.*?<status>([^<]+)</status>.*?</bash-notification>', text, re.DOTALL):
                                shell_id, status = match.groups()
                                if status == 'completed':
                                    completed_shell_ids.add(shell_id)

                        if not isinstance(block, dict):
                            continue

                        # Track tool_use blocks
                        if block.get('type') == 'tool_use':
                            name = block.get('name', '')
                            tool_id = block.get('id', '')
                            inp = block.get('input', {})

                            # Background Bash
                            if name == 'Bash' and inp.get('run_in_background'):
                                bg_shells[tool_id] = None  # Will be filled by tool_result

                            # TaskOutput retrieves agent results - mark agent as completed
                            if name == 'TaskOutput':
                                task_id = inp.get('task_id', '')
                                if task_id:
                                    completed_agent_ids.add(task_id)

                # Check entry-level toolUseResult for backgroundTaskId
                tool_result_obj = entry.get('toolUseResult', {})
                bg_task_id = tool_result_obj.get('backgroundTaskId')

                # If this entry has a backgroundTaskId, find the corresponding tool_use_id
                # from message.content[] blocks with type='tool_result'
                if bg_task_id and isinstance(content, list):
                    for block in content:
                        if isinstance(block, dict) and block.get('type') == 'tool_result':
                            tool_use_id = block.get('tool_use_id', '')
                            if tool_use_id in bg_shells:
                                bg_shells[tool_use_id] = bg_task_id
                                break

                # Check for agent launch - can be 'async_launched' or 'completed'
                if tool_result_obj.get('agentId'):
                    status = tool_result_obj.get('status', '')
                    if status in ['async_launched', 'completed']:
                        agent_id = tool_result_obj.get('agentId')
                        async_agent_ids.add(agent_id)

            except:
                pass

    # Debug: log what was found
    import sys
    sys.stderr.write(f'DEBUG PARSE: Found {len(async_agent_ids)} agents, {len(bg_shells)} shells\\n')
    sys.stderr.write(f'DEBUG PARSE: async_agent_ids={async_agent_ids}\\n')
    sys.stderr.write(f'DEBUG PARSE: completed_agent_ids={completed_agent_ids}\\n')
    sys.stderr.write(f'DEBUG PARSE: bg_shells={bg_shells}\\n')
    sys.stderr.write(f'DEBUG PARSE: completed_shell_ids={completed_shell_ids}\\n')

    # Calculate active background shells
    # A shell is active if its backgroundTaskId is NOT in completed_shell_ids
    active_shells = 0
    for tool_id, bg_task_id in bg_shells.items():
        if bg_task_id and bg_task_id not in completed_shell_ids:
            active_shells += 1

    # Filter agents - check if they're actually still running
    # An agent is considered complete if:
    # 1. TaskOutput was called for it, OR
    # 2. Its transcript file hasn't been modified in 10+ seconds
    active_agent_ids = []
    for aid in async_agent_ids:
        if aid in completed_agent_ids:
            continue  # Explicitly completed via TaskOutput
        # Check transcript file modification time
        agent_file = os.path.join(project_dir, f'agent-{aid}.jsonl')
        if os.path.exists(agent_file):
            mtime = os.path.getmtime(agent_file)
            age = time.time() - mtime
            if age < 10:  # Still being written to
                active_agent_ids.append(aid)
        # If file doesn't exist or is stale, agent is done

    # Build output parts
    parts = []

    # Agent info with context bars
    if active_agent_ids:
        agent_parts = []
        for agent_id in active_agent_ids:
            # Try to read agent transcript for context usage
            agent_file = os.path.join(project_dir, f'agent-{agent_id}.jsonl')
            pct = 0
            if os.path.exists(agent_file):
                try:
                    tokens = 0
                    with open(agent_file, 'r') as af:
                        for aline in af:
                            try:
                                aentry = json.loads(aline)
                                # Look for usage in message
                                usage = aentry.get('message', {}).get('usage', {})
                                if usage:
                                    tokens = max(tokens,
                                        usage.get('input_tokens', 0) +
                                        usage.get('cache_creation_input_tokens', 0) +
                                        usage.get('cache_read_input_tokens', 0))
                            except:
                                pass
                    if context_size > 0:
                        pct = min(100, int(tokens * 100 / context_size))
                except:
                    pass

            # Build mini bar (5 chars)
            filled = pct * 5 // 100
            bar = '█' * filled + '░' * (5 - filled)
            agent_parts.append(f'{agent_id} [{bar}] {pct}%')

        parts.append('🤖 ' + '  '.join(agent_parts))

    # Shell count
    if active_shells > 0:
        shell_word = 'shell' if active_shells == 1 else 'shells'
        parts.append(f'⏵ {active_shells} {shell_word}')

    # Debug logging
    import sys
    sys.stderr.write(f'DEBUG: active_agent_ids={len(active_agent_ids)}, active_shells={active_shells}, parts={parts}\\n')

    if parts:
        print(' | '.join(parts))
    else:
        print('')

except Exception as e:
    import sys
    sys.stderr.write(f'ERROR in background tracking: {e}\\n')
    print('')
" 2>>/tmp/statusline-background-debug.log)
fi

# Format output: Main line
printf "\033[0;36m%s\033[0m | \033[0;33m%s\033[0m | \033[0;32m%s\033[0m | 💰 \$%s" \
    "$REPO_INFO" "$CONTEXT_BAR" "$MODEL_DISPLAY" "$COST"

# Second line for background processes (if any)
if [ -n "$BACKGROUND_LINE" ]; then
    printf "\n%s" "$BACKGROUND_LINE"
fi
