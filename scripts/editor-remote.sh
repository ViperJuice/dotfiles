#!/bin/bash
# Editor remote wrapper — seamless cursor/code across SSH
# Detects if running in SSH session on headless machine and opens
# editor on the display machine using the --remote flag (IPC socket).
#
# On desktop (has $DISPLAY): passes through to the real binary
# On SSH remote: SSHs back to display machine and runs
#   $editor --remote ssh-remote+hostname /path
#
# Requires:
#   - Bidirectional SSH via Tailscale
#   - DOTFILES_DISPLAY_HOST env var (default: "display")

_editor_open_remote() {
    local editor="$1"
    shift
    local args=("$@")

    # On desktop: pass through to real binary
    if [ -n "$DISPLAY" ] || [ -n "$WAYLAND_DISPLAY" ]; then
        command "$editor" "${args[@]}"
        return
    fi

    # Not in SSH session: pass through
    if [ -z "$SSH_CONNECTION" ]; then
        command "$editor" "${args[@]}"
        return
    fi

    # SSH remote → resolve path, hostname, SSH back to display
    local target="${args[0]:-.}"
    [[ "$target" == "." ]] && target="$(pwd)"
    [[ "$target" != /* ]] && target="$(cd "$target" 2>/dev/null && pwd)"

    local remote_host
    remote_host=$(tailscale status --self --json 2>/dev/null \
        | python3 -c "import sys,json; print(json.load(sys.stdin)['Self']['DNSName'].split('.')[0])" 2>/dev/null)
    remote_host="${remote_host:-$(hostname)}"

    local display_host="${DOTFILES_DISPLAY_HOST:-display}"

    # Use --remote flag (IPC socket, no DISPLAY needed)
    if ssh -o ConnectTimeout=3 -o BatchMode=yes "$display_host" \
        "DISPLAY=:1 $editor --remote ssh-remote+${remote_host} '${target}'" 2>/dev/null; then
        echo "Opened ${editor} on ${display_host} → ${remote_host}:${target}"
    else
        echo "Could not reach ${display_host}. Falling back to tunnel..."
        command "$editor" tunnel --accept-server-license-terms
    fi
}

code()   { _editor_open_remote code   "$@"; }
cursor() { _editor_open_remote cursor "$@"; }
