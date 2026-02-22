# Dotfiles

Personal configuration for development environment, supporting five AI coding tools from a single source of truth with Zellij terminal multiplexer integration.

**Target platforms:** Ubuntu (cloud server) and WSL Ubuntu.

## Supported Tools

| Tool | Instructions | Commands | Agents | Skills | MCP Gateway |
|------|:-----------:|:--------:|:------:|:------:|:-----------:|
| Claude Code | CLAUDE.md | Shared + Claude | - | Yes | Yes |
| Codex | Project CLAUDE.md | - | - | Yes | - |
| OpenCode | - | Shared | Shared | - | Yes |
| Gemini CLI | GEMINI.md | - | - | - | Yes |
| Cursor IDE | .mdc rules | - | - | - | Yes |

## Quick Start

```bash
git clone <repo-url> ~/code/dotfiles
cd ~/code/dotfiles
./bootstrap.sh
```

The bootstrap script will:
1. **Auto-install dependencies** (git, python3, npm, Claude Code CLI)
2. **Build custom Zellij** from `~/code/zellij` (with pane targeting features)
3. **Authenticate Claude Code** (opens browser if needed)
4. **Configure your shell** with aliases and tab title
5. **Set up Zellij integration** (notifications, agent panes, background shells)
6. **Install skills** (WSL screenshots, Anthropic skills marketplace)
7. **Configure other tools** (OpenCode, Gemini CLI, Cursor IDE — if installed)
8. **Set up Obsidian docs sync** (hourly cron job)

Then restart your shell: `source ~/.zshrc` (or `~/.bashrc`)

## Custom Zellij Fork

This setup relies on a [custom Zellij fork](https://github.com/jenner/zellij) with additional CLI flags for automation:

- `--pane-id` on `rename-pane` - rename specific pane without focus
- `--stack-with` on `run` - stack new pane under specific pane
- `focus-pane-by-id` - focus a pane by its ID
- `--pane-id` on `close-pane`, `write-chars`, `dump-screen`
- `list-panes` - list all panes as JSON

The bootstrap script automatically builds and installs the custom binary to `~/.local/bin/zellij` if the source repo exists at `~/code/zellij` (configurable via `ZELLIJ_SRC_DIR` env var). Falls back to stock Zellij if the custom fork isn't available.

## Platform Support

| Feature | WSL | macOS | Linux |
|---------|:---:|:-----:|:-----:|
| Custom statusline | Yes | Yes | Yes |
| Tab title (repo:branch) | Yes | Yes | Yes |
| Zellij pane notifications | Yes | Yes | Yes |
| Agent transcript panes | Yes | Yes | Yes |
| Background shell panes | Yes | Yes | Yes |
| Audio notifications | Yes | Yes | Partial |
| Screenshots skill | Yes | - | - |

### Platform Notes

**WSL/Windows:**
- Screenshots folder auto-linked from Windows (`~/screenshots`)
- WSL-specific skills installed (wsl-screenshots)
- Audio via PowerShell beep (works through WSLg)
- Dependencies installed via `apt`

**macOS:**
- Audio via `afplay` system sounds
- Dependencies installed via Homebrew

**Linux:**
- Audio via PulseAudio (`paplay`) if available
- Dependencies installed via `apt` or package manager

## Features

### Custom Statusline (`statusline-custom.sh`)

A rich statusline showing:
```
repo (branch) | [=====>    ] 63% | S4.5 | $42.53
a301186 [==>  ] 32% | 1 shell
```

- Repository name and git branch
- Context window usage with visual progress bar
- Current model (abbreviated: H4.5, S4.5, O4.6)
- Session cost in USD
- Background agents with individual context usage
- Background shell count

See `claude-config/MODEL-CONFIG.md` for model configuration and CLI overrides.

### Stacked Pane Manager (`stacked-pane.sh`)

Unified pane management for both agent transcripts and background shells. When Claude spawns a subagent (Task tool) or runs a background command (Bash with `run_in_background`), a Zellij pane automatically opens stacked behind the parent Claude pane showing real-time output.

- **Agent panes**: Show parsed transcript (text + tool use indicators)
- **Shell panes**: Show raw command output via `tail -f`
- Panes auto-close when the process completes or times out
- Focus is preserved (never steals from user's active pane)
- Navigate stacked panes with `Alt+n` / `Alt+p`

### Notification System (`notify.sh` / `notify-clear.sh`)

When running Claude Code inside Zellij, notifications alert you when Claude needs attention:
- Renames pane/tab with bell icon (visible even when not focused)
- Plays audio notification (platform-specific, once per notification cycle)
- Clears automatically when you submit a prompt
- Session-aware: notification state isolated per Zellij session
- Original tab name preserved and restored on clear

### MCP Gateway

MCP (Model Context Protocol) servers provide additional tools and capabilities to Claude. Uses the **PMCP gateway** for unified server management.

Available servers (auto-start):
- **playwright** - Browser automation (navigation, screenshots, clicks)
- **context7** - Library documentation lookup
- **filesystem** - Access files in the dotfiles repository

The Context7 plugin is disabled in `settings.json` to use the gateway version instead. This keeps the context window cleaner and consolidates MCP tools through a single gateway.

See `claude-config/MCP-SETUP.md` for configuration details.

### Obsidian Docs Sync (`sync-obsidian-docs.sh`)

Syncs documentation from all repos in `~/code/` to an Obsidian vault:
- Scans for `docs/`, `ai-docs/`, `specs/`, `.claude/`, `.cursor/`, `.gemini/`
- Creates symlinks organized by repo and by type
- Cleans up broken symlinks
- Runs hourly via cron (installed by bootstrap)

### Skills

Skills are auto-invoked by Claude and Codex based on context. Bootstrap mirrors skills to `~/.claude/skills/` and `~/.codex/skills/`.

**wsl-screenshots** (WSL only) - Automatically activated when you mention screenshots, finds and displays Windows screenshots from `~/screenshots`.

See `claude-config/AGENTS.md` for information on creating custom skills. A template is available at `claude-config/skills/_template/`.

### Shell Enhancements

**Terminal Tab Title** - Automatically sets tab title to `repo:branch` format inside git repos.

**Claude Alias** - Adds `claude` alias with `--dangerously-skip-permissions` flag.

## Dependencies

### Required (auto-installed)
- **Git** - For repo/branch detection
- **Python 3** - For statusline JSON parsing
- **Claude Code CLI** - The whole point of this repo

### Optional (auto-installed if possible)
- **Rust toolchain** - For building custom Zellij fork
- **Zellij** - Terminal multiplexer for pane notifications and agent transcripts
- **pulseaudio-utils** - For native audio on Linux/WSL

## File Structure

```
dotfiles/
├── bootstrap.sh                # Installation script (run this!)
├── shared/                     # Cross-tool content (single source of truth)
│   ├── instructions/
│   │   └── core.md             # Universal dev instructions for all tools
│   ├── commands/
│   │   └── plan-detailed.md    # Shared slash command (Claude + OpenCode)
│   └── agents/
│       └── yolo.md             # Autonomous operator agent (OpenCode)
├── claude-config/              # Claude Code config (symlinked to ~/.claude/)
│   ├── settings.json           # Claude Code settings & hooks
│   ├── statusline-custom.sh    # Custom statusline script
│   ├── stacked-pane.sh         # Unified pane manager (agent + shell)
│   ├── agent-pane.sh           # Legacy agent pane script
│   ├── bash-pane.sh            # Legacy shell pane script
│   ├── notify.sh               # Zellij notification script
│   ├── notify-clear.sh         # Clears notifications on input
│   ├── sync-obsidian-docs.sh   # Obsidian vault docs sync
│   ├── check-zellij-pr.sh      # Monitors Zellij PR merge status
│   ├── skills/
│   │   ├── _template/          # Template for creating new skills
│   │   └── wsl-screenshots/    # WSL-only screenshot skill
│   │       └── SKILL.md
│   ├── CLAUDE.md               # Global Claude instructions
│   ├── AGENTS.md               # Agent-specific instructions
│   ├── MCP-SETUP.md            # MCP gateway configuration guide
│   └── MODEL-CONFIG.md         # Model selection and configuration
├── opencode-config/            # OpenCode-specific overrides (if any)
├── gemini-config/
│   └── GEMINI.md               # Template for Gemini instructions
├── cursor-config/
│   └── rules/
│       └── core-instructions.mdc  # Template for Cursor rules
├── zellij/
│   └── config.kdl              # Zellij config (scrollback, keybindings)
├── 1password/
│   └── env.op                  # 1Password secret references
├── anthropic-skills/           # Submodule: Anthropic skills marketplace
├── .env.example                # Template for secrets
├── .mcp.json                   # MCP gateway entry point (git-ignored)
├── .mcp.json.example           # Template for MCP gateway config
├── .pmcp.json                  # PMCP server configuration
└── .gitignore                  # Ignores secrets and temp files
```

## Debug Logging

All scripts log to `~/.cache/claude-dotfiles/logs/` when `CLAUDE_DOTFILES_DEBUG=1` is set:
- `statusline.log` - Statusline parsing and rendering
- `pane.log` - Stacked pane creation and focus management
- `notify.log` - Notification state and clearing

Enable with: `export CLAUDE_DOTFILES_DEBUG=1`

## Customization

### Modifying the Statusline

Edit `claude-config/statusline-custom.sh`. The script receives JSON from Claude Code via stdin and outputs formatted text. Uses a single Python invocation for both JSON parsing and background process tracking.

### Changing Colors

The output uses ANSI escape codes:
- `\033[0;36m` - Cyan (repo info)
- `\033[0;33m` - Yellow (context bar)
- `\033[0;32m` - Green (model name)

### Adding Skills

Use the skill-creator skill in Claude Code:
```bash
# In Claude Code:
/skill-creator
```

Or manually create from template:
```bash
cp -r ~/code/dotfiles/claude-config/skills/_template ~/code/dotfiles/claude-config/skills/my-skill
# Edit SKILL.md
ln -sf ~/code/dotfiles/claude-config/skills/my-skill ~/.claude/skills/my-skill
ln -sf ~/code/dotfiles/claude-config/skills/my-skill ~/.codex/skills/my-skill
```

See `claude-config/AGENTS.md` for detailed skill creation guide.

### Disabling Features

- **Agent/shell panes**: Remove the `PostToolUse` section from `settings.json`
- **Notifications**: Remove `Notification` and `Stop` sections from `settings.json`
- **Tab title**: Remove the `precmd`/`set_tab_title` managed block from your shell RC

## Troubleshooting

### Notifications not working

1. Must be running inside Zellij: `echo $ZELLIJ` should show a value
2. Check script is executable: `ls -la ~/.claude/notify.sh`
3. Test manually: `echo '{}' | ~/.claude/notify.sh`

### No audio

**WSL:** PowerShell must be accessible via `powershell.exe`
**macOS:** `afplay` should be available by default
**Linux:** Install `pulseaudio-utils`: `sudo apt install pulseaudio-utils`

### Stacked panes not opening

1. Must be running inside Zellij with the custom fork
2. Check hook is configured: `grep PostToolUse ~/.claude/settings.json`
3. Check script is executable: `chmod +x ~/.claude/stacked-pane.sh`
4. Enable debug logging: `export CLAUDE_DOTFILES_DEBUG=1`

### Custom Zellij build issues

1. Ensure Rust toolchain is installed: `rustup --version`
2. Check the source repo: `ls ~/code/zellij`
3. Build manually: `cd ~/code/zellij && git checkout feat/rename-pane-by-id && cargo xtask build`

## Uninstall

```bash
# Remove symlinks
rm -f ~/.claude/settings.json ~/.claude/statusline-custom.sh
rm -f ~/.claude/notify.sh ~/.claude/notify-clear.sh
rm -f ~/.claude/stacked-pane.sh ~/.claude/agent-pane.sh ~/.claude/bash-pane.sh
rm -rf ~/.claude/skills
rm -f ~/.codex/skills/*

# Remove shell config blocks (look for "# BEGIN DOTFILES:" markers)
# Edit ~/.zshrc and/or ~/.bashrc manually

# Optionally remove the repo
rm -rf ~/code/dotfiles
```

## Secrets & API Keys

Copy `.env.example` to `.env` for any API keys or secrets. The `.env` file is gitignored and will never be committed.

API keys managed via 1Password (`1password/env.op`):

| Key | Used By |
|-----|---------|
| `ANTHROPIC_API_KEY` | Claude Code, Codex |
| `OPENAI_API_KEY` | OpenCode, Cursor (API mode) |
| `GOOGLE_API_KEY` | Gemini CLI (API key auth) |
| `CEREBRAS_API_KEY` | Cerebras provider |
| `GROQ_API_KEY` | Groq provider |

Load all keys: `op-env` (shell helper added by bootstrap).

## License

Personal configuration - use as you wish.
