#!/bin/bash

# Read JSON input from stdin
input=$(cat)

# Extract all values using Python
eval $(python3 -c "
import json, shlex, os

try:
    d = json.loads('''$input''')

    # Basic fields
    model = d.get('model', {}).get('display_name', '?')
    cwd = d.get('cwd', d.get('workspace', {}).get('current_dir', '.'))
    cost = d.get('cost', {}).get('total_cost_usd', 0)
    transcript = d.get('transcript_path', '')

    # Context from current_usage (accurate) with fallback
    ctx = d.get('context_window', {})
    ctx_size = ctx.get('context_window_size', 200000)
    current = ctx.get('current_usage')

    if current and isinstance(current, dict):
        # Use current_usage: input + cache tokens
        tokens = (current.get('input_tokens', 0) +
                  current.get('cache_creation_input_tokens', 0) +
                  current.get('cache_read_input_tokens', 0))
    else:
        tokens = 0

    print(f'MODEL_DISPLAY={shlex.quote(model)}')
    print(f'CURRENT_DIR={shlex.quote(cwd)}')
    print(f'COST={cost:.2f}')
    print(f'TRANSCRIPT_PATH={shlex.quote(transcript)}')
    print(f'CONTEXT_SIZE={ctx_size}')
    print(f'TOKENS_USED={tokens}')
except Exception as e:
    print('MODEL_DISPLAY=\"?\"')
    print('CURRENT_DIR=\".\"')
    print('COST=0.00')
    print('TRANSCRIPT_PATH=\"\"')
    print('CONTEXT_SIZE=200000')
    print('TOKENS_USED=0')
" 2>/dev/null)

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

# Count active agents/tasks from transcript
AGENT_INFO=""
if [ -n "$TRANSCRIPT_PATH" ] && [ -f "$TRANSCRIPT_PATH" ]; then
    AGENT_COUNT=$(python3 -c "
import json

agents = set()
completed = set()

try:
    with open('$TRANSCRIPT_PATH', 'r') as f:
        for line in f:
            try:
                entry = json.loads(line)
                msg = entry.get('message', {})

                # Look for tool uses that spawn agents
                content = msg.get('content', [])
                if isinstance(content, list):
                    for block in content:
                        if isinstance(block, dict):
                            # Track Task tool calls (agent spawns)
                            if block.get('type') == 'tool_use':
                                name = block.get('name', '')
                                tool_id = block.get('id', '')
                                if name == 'Task' and tool_id:
                                    agents.add(tool_id)

                            # Track tool results (agent completions)
                            if block.get('type') == 'tool_result':
                                tool_id = block.get('tool_use_id', '')
                                if tool_id in agents:
                                    completed.add(tool_id)
            except:
                pass

    active = len(agents - completed)
    print(active)
except:
    print(0)
" 2>/dev/null)

    if [ -n "$AGENT_COUNT" ] && [ "$AGENT_COUNT" -gt 0 ] 2>/dev/null; then
        AGENT_INFO=" | 🤖 ${AGENT_COUNT}"
    fi
fi

# Format output: Repo | Context | Model | Cost | Agents (if any)
printf "\033[0;36m%s\033[0m | \033[0;33m%s\033[0m | \033[0;32m%s\033[0m | 💰 \$%s%s" \
    "$REPO_INFO" "$CONTEXT_BAR" "$MODEL_DISPLAY" "$COST" "$AGENT_INFO"
