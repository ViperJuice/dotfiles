#!/usr/bin/env bash
# Cleanup orphaned Claude Code and OpenCode sessions
# Runs every 5 minutes via cron to prevent OOM from leaked processes
#
# Improvements over v1:
# - SIGKILL escalation via state file (previously only sent SIGTERM, which spinning processes ignore)
# - Broader orphan detection (tsserver, eslint, mcp-index, not just pyright)
# - Swap pressure logging
# - 5-minute cron interval (was 30 minutes)

set -euo pipefail

LOG_TAG="cleanup-orphaned"
STATE_FILE="/tmp/.cleanup-orphaned-pending-kills"
log() { logger -t "$LOG_TAG" "$*"; }

killed=0
sigkilled=0

# ── 0. SIGKILL escalation: kill processes that survived SIGTERM from last run ──
if [[ -f "$STATE_FILE" ]]; then
    while IFS= read -r pid; do
        [[ -z "$pid" ]] && continue
        if ps -p "$pid" >/dev/null 2>&1; then
            cmd=$(ps -o args= -p "$pid" 2>/dev/null | head -c 120)
            log "SIGKILL escalation (survived SIGTERM): PID=$pid CMD=$cmd"
            kill -9 "$pid" 2>/dev/null && ((sigkilled++)) || true
        fi
    done < "$STATE_FILE"
    rm -f "$STATE_FILE"
fi

# Track PIDs we SIGTERM this run (for SIGKILL next run if they survive)
pending_kills=()

# ── 1. Kill claude/opencode processes that are orphaned or have dead terminals ──
while IFS= read -r line; do
    pid=$(echo "$line" | awk '{print $1}')
    tty=$(echo "$line" | awk '{print $2}')

    # Processes with no tty — check if reparented to init (orphaned)
    if [[ "$tty" == "?" ]]; then
        ppid=$(ps -o ppid= -p "$pid" 2>/dev/null | tr -d ' ')
        if [[ "$ppid" == "1" ]]; then
            cmd=$(ps -o args= -p "$pid" 2>/dev/null | head -c 120)
            log "Killing orphaned process (PPID=1): PID=$pid CMD=$cmd"
            kill "$pid" 2>/dev/null && { ((killed++)); pending_kills+=("$pid"); } || true
        fi
        continue
    fi

    # Processes whose pts device no longer exists
    if [[ "$tty" == pts/* ]] && [[ ! -e "/dev/$tty" ]]; then
        cmd=$(ps -o args= -p "$pid" 2>/dev/null | head -c 120)
        log "Killing process with dead terminal: PID=$pid TTY=$tty CMD=$cmd"
        kill "$pid" 2>/dev/null && { ((killed++)); pending_kills+=("$pid"); } || true
    fi
done < <(ps -eo pid,tty,args --no-headers | grep -iE '(claude|opencode|\.opencode)' | grep -v grep)

# ── 2. Kill orphaned language servers (PPID=1) ──
#    Covers pyright, tsserver, eslint, bash-language-server, typescript-language-server
while IFS= read -r line; do
    pid=$(echo "$line" | awk '{print $1}')
    ppid=$(echo "$line" | awk '{print $2}')
    if [[ "$ppid" == "1" ]]; then
        cmd=$(ps -o args= -p "$pid" 2>/dev/null | head -c 120)
        log "Killing orphaned language server: PID=$pid CMD=$cmd"
        kill "$pid" 2>/dev/null && { ((killed++)); pending_kills+=("$pid"); } || true
    fi
done < <(ps -eo pid,ppid,args --no-headers | grep -E '(pyright|bash-language-server|tsserver|eslint|typescript-language-server)' | grep -v grep)

# ── 3. Kill orphaned mcp-index processes (PPID=1, no terminal) ──
while IFS= read -r line; do
    pid=$(echo "$line" | awk '{print $1}')
    ppid=$(echo "$line" | awk '{print $2}')
    tty=$(echo "$line" | awk '{print $3}')
    if [[ "$ppid" == "1" ]] && [[ "$tty" == "?" ]]; then
        cmd=$(ps -o args= -p "$pid" 2>/dev/null | head -c 120)
        log "Killing orphaned mcp-index: PID=$pid CMD=$cmd"
        kill "$pid" 2>/dev/null && { ((killed++)); pending_kills+=("$pid"); } || true
    fi
done < <(ps -eo pid,ppid,tty,args --no-headers | grep 'mcp-index' | grep -v grep)

# ── 4. Kill orphaned playwright-mcp instances (PPID=1, no terminal) ──
while IFS= read -r line; do
    pid=$(echo "$line" | awk '{print $1}')
    ppid=$(echo "$line" | awk '{print $2}')
    tty=$(echo "$line" | awk '{print $3}')
    if [[ "$ppid" == "1" ]] && [[ "$tty" == "?" ]]; then
        cmd=$(ps -o args= -p "$pid" 2>/dev/null | head -c 120)
        log "Killing orphaned playwright-mcp: PID=$pid CMD=$cmd"
        kill "$pid" 2>/dev/null && { ((killed++)); pending_kills+=("$pid"); } || true
    fi
done < <(ps -eo pid,ppid,tty,args --no-headers | grep 'playwright-mcp' | grep -v grep)

# ── 5. Clean up exited zellij sessions ──
exited_sessions=$(zellij list-sessions 2>/dev/null | grep -c "EXITED" || true)
if [[ "$exited_sessions" -gt 0 ]]; then
    zellij delete-all-sessions -y 2>/dev/null && \
        log "Deleted $exited_sessions exited zellij session(s)" || true
fi

# ── 6. Kill orphaned node processes from uv builds (PPID=1) ──
while IFS= read -r line; do
    pid=$(echo "$line" | awk '{print $1}')
    cmd=$(ps -o args= -p "$pid" 2>/dev/null | head -c 120)
    log "Killing orphaned uv build process: PID=$pid CMD=$cmd"
    kill "$pid" 2>/dev/null && { ((killed++)); pending_kills+=("$pid"); } || true
done < <(ps -eo pid,ppid,args --no-headers | awk '$2==1 && /uv\/builds/ {print}')

# ── 7. Save pending kills for SIGKILL escalation on next run ──
if [[ ${#pending_kills[@]} -gt 0 ]]; then
    printf '%s\n' "${pending_kills[@]}" > "$STATE_FILE"
fi

# ── 8. Log swap pressure warning ──
if command -v free >/dev/null 2>&1; then
    swap_total=$(free -m | awk '/^Swap:/ {print $2}')
    swap_used=$(free -m | awk '/^Swap:/ {print $3}')
    if [[ "$swap_total" -gt 0 ]]; then
        swap_pct=$((swap_used * 100 / swap_total))
        if [[ "$swap_pct" -ge 75 ]]; then
            log "CRITICAL: Swap usage at ${swap_pct}% (${swap_used}MB/${swap_total}MB)"
        elif [[ "$swap_pct" -ge 50 ]]; then
            log "WARNING: Swap usage at ${swap_pct}% (${swap_used}MB/${swap_total}MB)"
        fi
    fi
fi

# ── Summary ──
if [[ "$killed" -gt 0 ]] || [[ "$sigkilled" -gt 0 ]]; then
    log "Cleaned up: $killed SIGTERM + $sigkilled SIGKILL"
else
    log "No orphaned processes found"
fi
