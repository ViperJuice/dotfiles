#!/bin/bash
# hosts/registry.sh — map a hostname to a deployment profile.
#
# Sourced by bootstrap.sh. Sets PROFILE to one of:
#   workstation         — full dev rig (Linux desktop / cloud dev box)
#   workstation-wsl     — full dev rig in WSL2 (no GUI notifications)
#   workstation-mac     — full dev rig on macOS
#   server              — headless infra host: lean plugins, no skipDangerous, sonnet model
#   appliance           — single-purpose box (Frigate, prod app server). Bootstrap refuses unless --force-profile.
#
# Override priority (highest wins):
#   1. CLI flag:           ./bootstrap.sh --profile=<name>
#   2. Env var:            DOTFILES_PROFILE=<name> ./bootstrap.sh
#   3. Hostname registry:  this file (Tailscale hostname preferred, then OS hostname)
#   4. Platform fallback:  linux→server, mac→workstation-mac, wsl→workstation-wsl

resolve_profile_from_hostname() {
    # Prefer Tailscale's tailnet hostname (stable across OS hostname renames)
    local ts=""
    if command -v tailscale >/dev/null 2>&1; then
        ts=$(tailscale status --self --json 2>/dev/null \
             | python3 -c "import sys,json;print(json.load(sys.stdin)['Self']['HostName'])" 2>/dev/null \
             | tr '[:upper:]' '[:lower:]')
    fi

    # Fall back to OS short hostname
    local os
    os=$(hostname -s 2>/dev/null | tr '[:upper:]' '[:lower:]')

    local h="${ts:-$os}"

    case "$h" in
        claw|clawdbot-*)              echo "workstation" ;;
        display|viperjuice-display-*) echo "workstation" ;;
        win-wsl)                      echo "workstation-wsl" ;;
        macmini|macmini-lan)          echo "workstation-mac" ;;
        ai|viperjuice-ai-*)           echo "server" ;;
        whathappened-prod|video-server) echo "appliance" ;;
        *)                            echo "" ;;
    esac
}
