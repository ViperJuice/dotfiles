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

# Track background processes from transcript
BACKGROUND_LINE=""
if [ -n "$TRANSCRIPT_PATH" ] && [ -f "$TRANSCRIPT_PATH" ]; then
    # Get project dir from transcript path for finding agent files
    PROJECT_DIR=$(dirname "$TRANSCRIPT_PATH")

    BACKGROUND_LINE=$(python3 -c "
import json
import os
import glob

transcript_path = '$TRANSCRIPT_PATH'
project_dir = '$PROJECT_DIR'
context_size = $CONTEXT_SIZE

# Track background processes
bg_shells = {}      # tool_id -> True (started)
bg_agents = {}      # tool_id -> agent_id
completed_tools = set()

try:
    with open(transcript_path, 'r') as f:
        for line in f:
            try:
                entry = json.loads(line)
                msg = entry.get('message', {})
                content = msg.get('content', [])

                if isinstance(content, list):
                    for block in content:
                        if not isinstance(block, dict):
                            continue

                        # Track tool_use blocks
                        if block.get('type') == 'tool_use':
                            name = block.get('name', '')
                            tool_id = block.get('id', '')
                            inp = block.get('input', {})

                            # Background Bash
                            if name == 'Bash' and inp.get('run_in_background'):
                                bg_shells[tool_id] = True

                            # Background Task (or any Task - they run async)
                            if name == 'Task' and inp.get('run_in_background'):
                                bg_agents[tool_id] = None  # agent_id comes in result

                        # Track tool_result blocks (completions)
                        if block.get('type') == 'tool_result':
                            tool_id = block.get('tool_use_id', '')
                            completed_tools.add(tool_id)

                # Check for toolUseResult with agentId (background agent spawned)
                tool_result = entry.get('toolUseResult', {})
                if tool_result.get('agentId'):
                    # Find which tool this agent belongs to
                    for tid in bg_agents:
                        if bg_agents[tid] is None:
                            bg_agents[tid] = tool_result['agentId']
                            break

            except:
                pass

    # Calculate active background processes
    active_shells = len([t for t in bg_shells if t not in completed_tools])
    active_agent_ids = [bg_agents[t] for t in bg_agents if t not in completed_tools and bg_agents[t]]

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

    if parts:
        print(' | '.join(parts))
    else:
        print('')

except Exception as e:
    print('')
" 2>/dev/null)
fi

# Format output: Main line
printf "\033[0;36m%s\033[0m | \033[0;33m%s\033[0m | \033[0;32m%s\033[0m | 💰 \$%s" \
    "$REPO_INFO" "$CONTEXT_BAR" "$MODEL_DISPLAY" "$COST"

# Second line for background processes (if any)
if [ -n "$BACKGROUND_LINE" ]; then
    printf "\n%s" "$BACKGROUND_LINE"
fi
