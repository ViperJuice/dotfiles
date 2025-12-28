# Dotfiles

Personal configuration files for development environment, focused on Claude Code CLI customization and terminal improvements for WSL/Windows Terminal.

## Quick Start

```bash
git clone <repo-url> ~/code/dotfiles
cd ~/code/dotfiles
./bootstrap.sh
```

Then restart your shell or run `source ~/.zshrc` (or `~/.bashrc`).

## What's Included

### Claude Code Configuration

**Custom Statusline** (`claude/statusline-custom.sh`)

A rich statusline showing:
```
📁 repo (branch) | [██████░░░░] 63% | Opus 4.5 | 💰 $42.53
🤖 a301186 [███░░] 32% | ⏵ 1 shell
```

- Repository name and git branch
- Context window usage with visual progress bar
- Current model name
- Session cost in USD
- Background agents with individual context usage
- Background shell count

**Settings** (`claude/settings.json`)

Configures Claude Code to use the custom statusline script.

### Shell Enhancements

**Terminal Tab Title** (added to `.zshrc`/`.bashrc`)

Automatically sets your terminal tab title to `repo:branch` format when inside a git repository, or the directory name otherwise. Works with Windows Terminal, iTerm2, and most modern terminals.

**Claude Alias**

Adds `claude` alias with `--dangerously-skip-permissions` flag for streamlined usage.

**Notification System** (`claude/notify.sh`)

When running Claude Code inside Zellij, notifications alert you when Claude needs attention:
- Renames pane to "🔔 claude" (visible in pane frame)
- Plays audio notification via `paplay` (native) or PowerShell beep (fallback)
- Automatically clears when you focus the pane
- Works inside Claude's TUI (doesn't require shell prompt)

## File Structure

```
dotfiles/
├── bootstrap.sh              # Installation script
├── claude/
│   ├── settings.json         # Claude Code settings
│   ├── statusline-custom.sh  # Custom statusline script
│   ├── notify.sh             # Zellij notification script
│   ├── CLAUDE.md             # Global Claude instructions
│   └── AGENTS.md             # Agent-specific instructions
├── .env.example              # Template for secrets
└── .gitignore                # Ignores secrets and temp files
```

## Requirements

- Bash or Zsh
- Python 3 (for statusline parsing)
- Git
- [Claude Code CLI](https://github.com/anthropics/claude-code)

### Optional (for Zellij notifications)

- [Zellij](https://zellij.dev/) - Terminal multiplexer
- `pulseaudio-utils` - For native audio notifications in WSL2/WSLg
  ```bash
  sudo apt install pulseaudio-utils
  ```

## Installation Details

The `bootstrap.sh` script:

1. Creates `~/.claude/` directory if needed
2. Symlinks Claude config files (settings.json, statusline-custom.sh, notify.sh)
3. Installs `pulseaudio-utils` if not present (for audio notifications)
4. Adds the `claude` alias to your shell RC file
5. Adds terminal tab title configuration with Zellij notification clearing

All additions are idempotent - running bootstrap multiple times is safe.

## Customization

### Modifying the Statusline

Edit `claude/statusline-custom.sh`. The script receives JSON from Claude Code via stdin and outputs formatted text.

Key sections:
- Lines 7-45: Parse JSON input (model, cost, context, etc.)
- Lines 47-59: Git repo/branch detection
- Lines 61-78: Context bar rendering
- Lines 80-198: Background process tracking
- Lines 201-208: Final output formatting

### Changing Colors

The output uses ANSI escape codes:
- `\033[0;36m` - Cyan (repo info)
- `\033[0;33m` - Yellow (context bar)
- `\033[0;32m` - Green (model name)

### Disabling Features

To disable the tab title feature, remove or comment out the `precmd` function (Zsh) or `set_tab_title` function (Bash) from your shell RC file.

## Secrets

Copy `.env.example` to `.env` for any API keys or secrets. The `.env` file is gitignored and will never be committed.

## License

Personal configuration - use as you wish.
