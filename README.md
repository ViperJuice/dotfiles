# Dotfiles

Personal configuration files for development environment, focused on Claude Code CLI customization and terminal improvements.

## Quick Start

```bash
git clone <repo-url> ~/code/dotfiles
cd ~/code/dotfiles
./bootstrap.sh
```

The bootstrap script will:
1. **Auto-install dependencies** (git, python3, npm, Claude Code CLI, Zellij)
2. **Authenticate Claude Code** (opens browser if needed)
3. **Configure your shell** with aliases and tab title
4. **Set up Zellij notifications** for when Claude needs attention
5. **Install platform-specific skills** (e.g., WSL screenshots)

Then restart your shell: `source ~/.zshrc` (or `~/.bashrc`)

## Platform Support

| Feature | WSL | macOS | Linux |
|---------|:---:|:-----:|:-----:|
| Custom statusline | Yes | Yes | Yes |
| Tab title (repo:branch) | Yes | Yes | Yes |
| Zellij pane notifications | Yes | Yes | Yes |
| Agent transcript panes | Yes | Yes | Yes |
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

## What's Included

### Claude Code Configuration

**Custom Statusline** (`claude/statusline-custom.sh`)

A rich statusline showing:
```
repo (branch) | [=====>    ] 63% | Opus 4.5 | $42.53
a301186 [==>  ] 32% | 1 shell
```

- Repository name and git branch
- Context window usage with visual progress bar
- Current model name
- Session cost in USD
- Background agents with individual context usage
- Background shell count

**Agent Transcript Panes** (`claude/agent-pane.sh`)

When Claude spawns a subagent (Task tool), a Zellij pane automatically opens below showing the agent's transcript in real-time. Panes close automatically when the agent completes.

**Notification System** (`claude/notify.sh`)

When running Claude Code inside Zellij, notifications alert you when Claude needs attention:
- Renames pane/tab with bell icon (visible even when not focused)
- Plays audio notification (platform-specific)
- Clears automatically when you submit a prompt

**Settings** (`claude/settings.json`)

Configures:
- Custom statusline script
- Notification hooks (idle, permission prompts, stop)
- Agent pane hooks (PostToolUse for Task)
- Auto-clear notification on prompt submit

### Skills

Skills are auto-invoked by Claude based on context. Located in `~/.claude/skills/`.

**wsl-screenshots** (WSL only)
- Automatically activated when you mention screenshots
- Finds and displays Windows screenshots from `~/screenshots`

### Shell Enhancements

**Terminal Tab Title**

Automatically sets your terminal tab title to `repo:branch` format when inside a git repository, or the directory name otherwise.

**Claude Alias**

Adds `claude` alias with `--dangerously-skip-permissions` flag.

## Dependencies

### Required (auto-installed)
- **Git** - For repo/branch detection
- **Python 3** - For statusline JSON parsing
- **Claude Code CLI** - The whole point of this repo

### Optional (auto-installed if possible)
- **Zellij** - Terminal multiplexer for pane notifications and agent transcripts
- **pulseaudio-utils** - For native audio on Linux/WSL

## File Structure

```
dotfiles/
├── bootstrap.sh              # Installation script (run this!)
├── claude/
│   ├── settings.json         # Claude Code settings & hooks
│   ├── statusline-custom.sh  # Custom statusline script
│   ├── notify.sh             # Zellij notification script
│   ├── notify-clear.sh       # Clears notifications on input
│   ├── agent-pane.sh         # Opens Zellij panes for agent transcripts
│   ├── skills/
│   │   └── wsl-screenshots/  # WSL-only screenshot skill
│   │       └── SKILL.md
│   ├── CLAUDE.md             # Global Claude instructions
│   └── AGENTS.md             # Agent-specific instructions
├── .env.example              # Template for secrets
└── .gitignore                # Ignores secrets and temp files
```

## Customization

### Modifying the Statusline

Edit `claude/statusline-custom.sh`. The script receives JSON from Claude Code via stdin and outputs formatted text.

Key sections:
- Lines 7-45: Parse JSON input (model, cost, context, etc.)
- Lines 47-59: Git repo/branch detection
- Lines 61-78: Context bar rendering
- Lines 80-150: Background process tracking (agents and shells)
- Lines 155+: Final output formatting

### Changing Colors

The output uses ANSI escape codes:
- `\033[0;36m` - Cyan (repo info)
- `\033[0;33m` - Yellow (context bar)
- `\033[0;32m` - Green (model name)

### Adding Skills

Create a new skill directory in `claude/skills/`:

```
claude/skills/my-skill/
└── SKILL.md
```

SKILL.md format:
```markdown
---
name: my-skill
description: When to use this skill (Claude matches against this)
---

# Instructions

Your skill instructions here...
```

Update `bootstrap.sh` to symlink it (optionally with platform checks).

### Disabling Features

To disable the tab title feature, remove or comment out the `precmd` function (Zsh) or `set_tab_title` function (Bash) from your shell RC file.

To disable agent panes, remove the `PostToolUse` section from `claude/settings.json`.

## Troubleshooting

### Notifications not working

1. Make sure you're running inside Zellij: `echo $ZELLIJ` should show a value
2. Check the script is executable: `ls -la ~/.claude/notify.sh`
3. Test manually: `echo '{}' | ~/.claude/notify.sh`

### No audio

**WSL:** PowerShell must be accessible via `powershell.exe`
**macOS:** `afplay` should be available by default
**Linux:** Install `pulseaudio-utils`: `sudo apt install pulseaudio-utils`

### Statusline not showing

1. Check Claude Code settings: `cat ~/.claude/settings.json`
2. Make sure script is executable: `chmod +x ~/.claude/statusline-custom.sh`
3. Test manually: `echo '{}' | ~/.claude/statusline-custom.sh`

### Background agents not showing in statusline

The statusline tracks agents launched with `run_in_background: true`. Agents are removed from the display when their results are retrieved via `TaskOutput`.

### Agent panes not opening

1. Must be running inside Zellij
2. Check hook is configured: `grep PostToolUse ~/.claude/settings.json`
3. Check script is executable: `chmod +x ~/.claude/agent-pane.sh`

### Skills not found

1. Check skills directory exists: `ls ~/.claude/skills/`
2. Verify skill structure: each skill needs a `SKILL.md` file
3. Skills are matched by description - make sure it describes when to use

### Claude Code not authenticated

Run `claude` in your terminal and complete the browser authentication flow.

## Uninstall

```bash
# Remove symlinks
rm -f ~/.claude/settings.json ~/.claude/statusline-custom.sh
rm -f ~/.claude/notify.sh ~/.claude/notify-clear.sh ~/.claude/agent-pane.sh
rm -rf ~/.claude/skills

# Remove shell config blocks (look for "# BEGIN DOTFILES:" markers)
# Edit ~/.zshrc and/or ~/.bashrc manually

# Optionally remove the repo
rm -rf ~/code/dotfiles
```

## Secrets

Copy `.env.example` to `.env` for any API keys or secrets. The `.env` file is gitignored and will never be committed.

## License

Personal configuration - use as you wish.
