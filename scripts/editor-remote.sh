#!/bin/bash
# Editor remote wrapper — seamless cursor/code across SSH
# Detects if running in SSH session on headless machine and opens
# editor on the display machine via --folder-uri with vscode-remote:// URI.
#
# Requires:
#   - Bidirectional SSH via Tailscale
#   - DOTFILES_DISPLAY_HOST env var (default: "display")
#   - xxd (from vim-common) for hex encoding

_editor_open_remote() {
    local editor="$1"
    shift
    local args=("$@")

    # Inside a Cursor/VS Code integrated terminal: use native IPC
    if [ -n "$VSCODE_IPC_HOOK_CLI" ]; then
        command "$editor" "${args[@]}"
        return
    fi

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

    # SSH remote → build vscode-remote URI → open on display machine
    local target="${args[0]:-.}"
    [[ "$target" == "." ]] && target="$(pwd)"
    [[ "$target" != /* ]] && target="$(cd "$target" 2>/dev/null && pwd)"

    local remote_host
    remote_host=$(tailscale status --self --json 2>/dev/null \
        | python3 -c "import sys,json; print(json.load(sys.stdin)['Self']['DNSName'].split('.')[0])" 2>/dev/null)
    remote_host="${remote_host:-$(hostname)}"

    local display_host="${DOTFILES_DISPLAY_HOST:-display}"

    # Build vscode-remote URI with hex-encoded JSON hostname
    local hex_host
    hex_host=$(printf '{"hostName":"%s"}' "$remote_host" | xxd -p | tr -d '\n')
    local uri="vscode-remote://ssh-remote+${hex_host}${target}"

    # SSH to display, detect XAUTHORITY dynamically, open with --folder-uri
    if ssh -o ConnectTimeout=3 -o BatchMode=yes "$display_host" \
        "export DISPLAY=:0; \
         export XAUTHORITY=\$(pgrep -a Xwayland | grep -o '/run/user/[0-9]*/\.mutter-Xwaylandauth\.[A-Za-z0-9]*'); \
         ELECTRON_RUN_AS_NODE=1 /usr/share/cursor/cursor /usr/share/cursor/resources/app/out/cli.js \
         --folder-uri '${uri}' --reuse-window" 2>/dev/null; then
        echo "Opened ${editor} on ${display_host} → ${remote_host}:${target}"
    else
        echo "Could not reach ${display_host}. Falling back to tunnel..."
        command "$editor" tunnel --accept-server-license-terms
    fi
}

code()   { _editor_open_remote code   "$@"; }
cursor() { _editor_open_remote cursor "$@"; }
