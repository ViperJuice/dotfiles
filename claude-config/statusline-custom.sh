#!/bin/bash

# Read JSON input from stdin
input=$(cat)

# Unified log directory
LOG_DIR="${HOME}/.cache/claude-dotfiles/logs"

# Debug logging (opt-in)
debug_log() {
    if [[ -n "$CLAUDE_DOTFILES_DEBUG" ]]; then
        mkdir -p "$LOG_DIR" 2>/dev/null
        echo "[$(date '+%H:%M:%S')] $*" >> "$LOG_DIR/statusline.log"
    fi
}

# Single Python invocation: parse JSON input + scan background processes
# All values communicated via tab-delimited stdout (no eval)
IFS=$'\t' read -r MODEL_DISPLAY CURRENT_DIR COST TRANSCRIPT_PATH CONTEXT_SIZE TOKENS_USED BACKGROUND_LINE <<< "$(echo "$input" | python3 -c "
import sys, json, os, time, glob, re

def abbreviate_model(name):
    '''Abbreviate model names to compact format: H4.5, S4.5, O4.6'''
    name_lower = name.lower()

    # Determine model family
    if 'haiku' in name_lower or name_lower.startswith('h'):
        family = 'H'
    elif 'sonnet' in name_lower or 'sun' in name_lower or name_lower.startswith('s'):
        family = 'S'
    elif 'opus' in name_lower or name_lower.startswith('o'):
        family = 'O'
    else:
        return name  # Unknown format, return as-is

    # Extract version like \"4.5\", \"4.6\"
    version_match = re.search(r'(\d+)\.(\d+)', name)
    if version_match:
        return f'{family}{version_match.group(1)}.{version_match.group(2)}'
    return name

try:
    d = json.load(sys.stdin)

    # Basic fields with multiple fallback paths
    model_obj = d.get('model', {})
    if isinstance(model_obj, dict):
        model = model_obj.get('display_name') or model_obj.get('name', '?')
    else:
        model = str(model_obj) if model_obj else '?'

    # Abbreviate model name for compact display
    model = abbreviate_model(model)

    cwd = d.get('cwd') or d.get('workspace', {}).get('current_dir', '.')

    cost_obj = d.get('cost', {})
    cost = cost_obj.get('total_cost_usd', 0) if isinstance(cost_obj, dict) else 0

    transcript = d.get('transcript_path', '')

    # Context from current_usage (accurate) with fallback
    ctx = d.get('context_window', {})
    ctx_size = ctx.get('context_window_size', 200000) if isinstance(ctx, dict) else 200000
    current = ctx.get('current_usage') if isinstance(ctx, dict) else None

    if current and isinstance(current, dict):
        tokens = (current.get('input_tokens', 0) +
                  current.get('cache_creation_input_tokens', 0) +
                  current.get('cache_read_input_tokens', 0))
    else:
        tokens = 0

    # === Background process tracking ===
    bg_line = ''
    if transcript and os.path.isfile(transcript):
        project_dir = os.path.dirname(transcript)

        bg_shells = {}
        completed_agent_ids = set()

        # Parse CURRENT transcript only (not all transcripts - too expensive)
        with open(transcript, 'r') as f:
            for line in f:
                try:
                    entry = json.loads(line)
                    msg = entry.get('message', {})
                    content = msg.get('content', [])

                    if isinstance(content, list):
                        for block in content:
                            if not isinstance(block, dict):
                                continue

                            if block.get('type') == 'tool_use':
                                name = block.get('name', '')
                                tool_id = block.get('id', '')
                                inp = block.get('input', {})

                                if name == 'Bash' and inp.get('run_in_background'):
                                    bg_shells[tool_id] = None

                                if name == 'TaskOutput':
                                    task_id = inp.get('task_id', '')
                                    if task_id:
                                        completed_agent_ids.add(task_id)

                    # Check for completed agents from toolUseResult
                    tool_result_obj = entry.get('toolUseResult', {})
                    if tool_result_obj.get('agentId'):
                        status = tool_result_obj.get('status', '')
                        if status in ('completed', 'failed'):
                            completed_agent_ids.add(tool_result_obj.get('agentId'))

                    bg_task_id = tool_result_obj.get('backgroundTaskId')
                    if bg_task_id and isinstance(content, list):
                        for block in content:
                            if isinstance(block, dict) and block.get('type') == 'tool_result':
                                tool_use_id = block.get('tool_use_id', '')
                                if tool_use_id in bg_shells:
                                    bg_shells[tool_use_id] = bg_task_id
                                    break
                except:
                    pass

        # Count active background shells
        project_slug = os.path.basename(project_dir)
        tasks_dir = f'/tmp/claude/{project_slug}/tasks'
        active_shells = 0

        for tool_id, bg_task_id in bg_shells.items():
            if bg_task_id:
                if bg_task_id in completed_agent_ids:
                    continue
                output_file = os.path.join(tasks_dir, f'{bg_task_id}.output')
                if os.path.exists(output_file):
                    mtime = os.path.getmtime(output_file)
                    if time.time() - mtime < 10:
                        active_shells += 1

        # Find active agents
        active_agent_ids = []
        agent_pattern = os.path.join(project_dir, 'agent-*.jsonl')
        for agent_file in glob.glob(agent_pattern):
            mtime = os.path.getmtime(agent_file)
            if time.time() - mtime >= 300:
                continue

            basename_f = os.path.basename(agent_file)
            if not (basename_f.startswith('agent-') and basename_f.endswith('.jsonl')):
                continue
            aid = basename_f[6:-6]

            if aid in completed_agent_ids:
                continue

            try:
                with open(agent_file, 'r') as af:
                    last_line = None
                    for aline in af:
                        last_line = aline
                    if last_line:
                        last_msg = json.loads(last_line)
                        stop_reason = last_msg.get('message', {}).get('stop_reason')
                        if stop_reason and stop_reason != 'None':
                            continue
            except:
                pass

            active_agent_ids.append(aid)

        # Build background line
        parts = []
        if active_agent_ids:
            agent_parts = []
            for agent_id in active_agent_ids:
                agent_file = os.path.join(project_dir, f'agent-{agent_id}.jsonl')
                pct = 0
                if os.path.exists(agent_file):
                    try:
                        atokens = 0
                        with open(agent_file, 'r') as af:
                            for aline in af:
                                try:
                                    aentry = json.loads(aline)
                                    usage = aentry.get('message', {}).get('usage', {})
                                    if usage:
                                        atokens = max(atokens,
                                            usage.get('input_tokens', 0) +
                                            usage.get('cache_creation_input_tokens', 0) +
                                            usage.get('cache_read_input_tokens', 0))
                                except:
                                    pass
                        if ctx_size > 0:
                            pct = min(100, int(atokens * 100 / ctx_size))
                    except:
                        pass

                filled = pct * 5 // 100
                bar = '\u2588' * filled + '\u2591' * (5 - filled)
                agent_parts.append(f'{agent_id} [{bar}] {pct}%')

            parts.append('\U0001f916 ' + '  '.join(agent_parts))

        if active_shells > 0:
            shell_word = 'shell' if active_shells == 1 else 'shells'
            parts.append(f'\u23f5 {active_shells} {shell_word}')

        bg_line = ' | '.join(parts)

    # Output all values tab-delimited (safe: no eval)
    # Use '-' as placeholder for empty strings to prevent read field shifting
    print(str(model) or '-', str(cwd) or '-', f'{float(cost):.2f}',
          str(transcript) or '-', str(int(ctx_size)), str(int(tokens)),
          bg_line or '-', sep='\t')

except Exception as e:
    import sys as _sys
    _sys.stderr.write(f'ERROR in statusline: {e}\n')
    print('?', '.', '0.00', '-', '200000', '0', '-', sep='\t')
" 2>/dev/null)"

debug_log "model=$MODEL_DISPLAY dir=$CURRENT_DIR cost=$COST tokens=$TOKENS_USED"

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
for _i in $(seq 1 $FILLED_CHARS); do CONTEXT_BAR="${CONTEXT_BAR}█"; done
for _i in $(seq 1 $EMPTY_CHARS); do CONTEXT_BAR="${CONTEXT_BAR}░"; done
CONTEXT_BAR="${CONTEXT_BAR}] ${PERCENT_USED}%"

# Format output: Main line
printf "\033[0;36m%s\033[0m | \033[0;33m%s\033[0m | \033[0;32m%s\033[0m | 💰 \$%s" \
    "$REPO_INFO" "$CONTEXT_BAR" "$MODEL_DISPLAY" "$COST"

# Second line for background processes (if any)
if [ -n "$BACKGROUND_LINE" ] && [ "$BACKGROUND_LINE" != "-" ]; then
    printf "\n%s" "$BACKGROUND_LINE"
fi
