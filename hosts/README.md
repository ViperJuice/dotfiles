# Per-host Profiles

`bootstrap.sh` selects one of these profiles based on the machine and copies
its `settings.json` to `~/.claude/settings.local.json`. Claude Code merges
`settings.local.json` over `~/.claude/settings.json` (the safe base from
`claude-config/settings.json`).

## Profiles

| Profile | For | Key traits |
|---|---|---|
| `workstation` | Linux desktop dev (claw, display) | `model: opus`, hooks, statusline, `skipDangerousModePermissionPrompt: true`, `permissions.defaultMode: auto`, full dev plugins (frontend-design, playwright, vercel, codex) |
| `workstation-wsl` | Windows + WSL2 (win-wsl) | Same as workstation BUT no `hooks` block (the GUI notifier scripts are zellij-gated and pointless when the user is on the Windows side) |
| `workstation-mac` | macOS desktop / VNC'd Mac (macmini) | Same as workstation; `notify.sh` already branches on Darwin for audio |
| `server` | Headless infra (ai) | `model: sonnet` (cheaper for ops), no hooks, **no** `skipDangerousModePermissionPrompt`, **no** `permissions.defaultMode: auto`, lean plugin set |
| `appliance` | Single-purpose appliances (whathappened-prod, video-server) | Bootstrap *refuses* to deploy here unless `--force-profile=<name>` is passed. The expectation is these hosts run plain CC with default settings, or no CC at all. |

## How selection works

Resolution order (highest wins):

1. `./bootstrap.sh --profile=<name>` (CLI flag)
2. `DOTFILES_PROFILE=<name> ./bootstrap.sh` (env var)
3. `hosts/registry.sh` hostname → profile lookup
4. Platform fallback: linux→server, mac→workstation-mac, wsl→workstation-wsl

## Adding a new host

Edit `hosts/registry.sh` and add the hostname to a `case` arm. If a brand-new
profile is needed, also create `hosts/<profile>/settings.json` and document it
in this table.

## Why an overlay (not the symlinked base)?

`~/.claude/settings.local.json` is a *copy*, not a symlink. That way the user
can hand-edit it on a host (e.g. switch one machine to sonnet temporarily) without
the next bootstrap stomping it. Pass `--force-profile` to force-overwrite.
