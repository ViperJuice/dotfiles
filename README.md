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

Then restart your shell: `source ~/.zshrc` (or `~/.bashrc`)

## Platform Support

| Feature | WSL | macOS | Linux |
|---------|:---:|:-----:|:-----:|
| Custom statusline | Yes | Yes | Yes |
| Tab title (repo:branch) | Yes | Yes | Yes |
| Zellij pane notifications | Yes | Yes | Yes |
| Audio notifications | Yes | Yes | Partial |
| Screenshots symlink | Yes | - | - |

### Platform Notes

**WSL/Windows:**
- Screenshots folder auto-linked from Windows (`~/screenshots`)
- Audio via PowerShell beep (works through WSLg)
- Dependencies installed via `apt`

**macOS:**
- Audio via `afplay` system sounds
- Dependencies installed via Homebrew
- No Screenshots symlink (not applicable)

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

**Notification System** (`claude/notify.sh`)

When running Claude Code inside Zellij, notifications alert you when Claude needs attention:
- Renames pane to "repo:branch" (visible in pane frame)
- Plays audio notification (platform-specific)
- Clears automatically when you submit a prompt or press Enter

**Settings** (`claude/settings.json`)

Configures:
- Custom statusline script
- Notification hooks (idle, permission prompts, stop)
- Auto-clear notification on prompt submit

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
- **Zellij** - Terminal multiplexer for pane notifications
- **pulseaudio-utils** - For native audio on Linux/WSL

## File Structure

```
dotfiles/
├── bootstrap.sh              # Installation script (run this!)
├── claude/
│   ├── settings.json         # Claude Code settings & hooks
│   ├── statusline-custom.sh  # Custom statusline script
│   ├── notify.sh             # Zellij notification script
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
- Lines 80-198: Background process tracking
- Lines 201-208: Final output formatting

### Changing Colors

The output uses ANSI escape codes:
- `\033[0;36m` - Cyan (repo info)
- `\033[0;33m` - Yellow (context bar)
- `\033[0;32m` - Green (model name)

### Disabling Features

To disable the tab title feature, remove or comment out the `precmd` function (Zsh) or `set_tab_title` function (Bash) from your shell RC file.

## Troubleshooting

### Notifications not working

1. Make sure you're running inside Zellij: `echo $ZELLIJ` should show a value
2. Check the script is executable: `ls -la ~/.claude/notify.sh`
3. Test manually: `~/.claude/notify.sh`

### No audio

**WSL:** PowerShell must be accessible via `powershell.exe`
**macOS:** `afplay` should be available by default
**Linux:** Install `pulseaudio-utils`: `sudo apt install pulseaudio-utils`

### Statusline not showing

1. Check Claude Code settings: `cat ~/.claude/settings.json`
2. Make sure script is executable: `chmod +x ~/.claude/statusline-custom.sh`
3. Test manually: `echo '{}' | ~/.claude/statusline-custom.sh`

### Claude Code not authenticated

Run `claude` in your terminal and complete the browser authentication flow.

## Uninstall

```bash
# Remove symlinks
rm -f ~/.claude/settings.json ~/.claude/statusline-custom.sh ~/.claude/notify.sh

# Remove shell config blocks (look for "# BEGIN DOTFILES:" markers)
# Edit ~/.zshrc and/or ~/.bashrc manually

# Optionally remove the repo
rm -rf ~/code/dotfiles
```

## Secrets

Copy `.env.example` to `.env` for any API keys or secrets. The `.env` file is gitignored and will never be committed.

## License

Personal configuration - use as you wish.
