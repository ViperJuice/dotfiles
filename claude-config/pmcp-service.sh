#!/bin/bash
# pmcp-service.sh — Manual management for PMCP MCP Gateway
# Fallback for environments without systemd user services.
# Normally the systemd unit (pmcp.service) handles this automatically.

set -euo pipefail

PMCP_BIN="${PMCP_BIN:-$HOME/.local/bin/pmcp}"
PMCP_CONFIG="${PMCP_CONFIG:-$HOME/.pmcp.json}"
PMCP_ENV="${PMCP_ENV:-$HOME/.config/pmcp/pmcp.env}"
PMCP_HOST="127.0.0.1"
PMCP_PORT="3344"
PMCP_PID_FILE="${XDG_RUNTIME_DIR:-/tmp}/pmcp.pid"
PMCP_LOG="${XDG_CACHE_HOME:-$HOME/.cache}/pmcp/pmcp.log"

usage() {
    echo "Usage: $(basename "$0") {start|stop|restart|status|logs}"
    echo ""
    echo "Manages the PMCP MCP Gateway as a background process."
    echo "Prefer 'systemctl --user {start|stop|restart|status} pmcp' when available."
    exit 1
}

load_env() {
    if [[ -f "$PMCP_ENV" ]]; then
        set -a
        # shellcheck disable=SC1090
        source "$PMCP_ENV"
        set +a
    fi
}

get_pid() {
    if [[ -f "$PMCP_PID_FILE" ]]; then
        local pid
        pid=$(cat "$PMCP_PID_FILE")
        if kill -0 "$pid" 2>/dev/null; then
            echo "$pid"
            return 0
        fi
        rm -f "$PMCP_PID_FILE"
    fi
    return 1
}

do_start() {
    if pid=$(get_pid); then
        echo "PMCP already running (PID $pid)"
        return 0
    fi

    if [[ ! -x "$PMCP_BIN" ]] && ! command -v pmcp &>/dev/null; then
        echo "Error: pmcp not found at $PMCP_BIN"
        echo "Install with: uv tool install pmcp"
        exit 1
    fi

    load_env
    mkdir -p "$(dirname "$PMCP_LOG")"

    echo "Starting PMCP on $PMCP_HOST:$PMCP_PORT..."
    nohup "$PMCP_BIN" -c "$PMCP_CONFIG" \
        --transport http --host "$PMCP_HOST" --port "$PMCP_PORT" \
        -l info \
        >> "$PMCP_LOG" 2>&1 &

    echo $! > "$PMCP_PID_FILE"
    echo "PMCP started (PID $!)"
}

do_stop() {
    if pid=$(get_pid); then
        echo "Stopping PMCP (PID $pid)..."
        kill "$pid"
        rm -f "$PMCP_PID_FILE"
        echo "PMCP stopped"
    else
        echo "PMCP is not running"
    fi
}

do_status() {
    if pid=$(get_pid); then
        echo "PMCP is running (PID $pid)"
        # Quick health check
        if curl -sf "http://$PMCP_HOST:$PMCP_PORT/sse" --max-time 2 -o /dev/null 2>/dev/null; then
            echo "SSE endpoint: http://$PMCP_HOST:$PMCP_PORT/sse ✓"
        else
            echo "SSE endpoint: http://$PMCP_HOST:$PMCP_PORT/sse (not responding)"
        fi
    else
        echo "PMCP is not running"
        return 1
    fi
}

do_logs() {
    if [[ -f "$PMCP_LOG" ]]; then
        tail -f "$PMCP_LOG"
    else
        echo "No log file found at $PMCP_LOG"
        echo "If using systemd: journalctl --user -u pmcp -f"
    fi
}

case "${1:-}" in
    start)   do_start ;;
    stop)    do_stop ;;
    restart) do_stop; sleep 1; do_start ;;
    status)  do_status ;;
    logs)    do_logs ;;
    *)       usage ;;
esac
