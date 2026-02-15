# Global Agent Instructions

See `~/.claude/skills/` and `~/.codex/skills/` for available skills.

## Creating Custom Skills

Skills extend Claude's capabilities with specialized knowledge, workflows, or tool integrations. They auto-trigger based on context described in the frontmatter.

### Quick Start

1. **Use the skill-creator skill**: The fastest way to create a new skill
   ```bash
   # In Claude Code:
   /skill-creator
   ```

2. **Use the template**: Copy `~/code/dotfiles/claude-config/skills/_template/` to start manually
   ```bash
   cp -r ~/code/dotfiles/claude-config/skills/_template ~/code/dotfiles/claude-config/skills/my-skill
   # Edit SKILL.md with your skill content
   # Symlink to ~/.claude/skills/my-skill and ~/.codex/skills/my-skill for testing
   ```

### Skill Structure

```
my-skill/
├── SKILL.md (required)          # Main skill definition
│   ├── YAML frontmatter:
│   │   ├── name: skill-identifier
│   │   └── description: when to trigger this skill
│   └── Markdown instructions
├── scripts/ (optional)           # Reusable code (Python/Bash)
├── references/ (optional)        # Detailed docs (loaded on demand)
└── assets/ (optional)            # Templates/resources
```

### Key Principles

- **Description is critical**: The frontmatter `description` field determines when Claude auto-triggers this skill
- **Keep SKILL.md concise**: You share the context window with conversation
- **Use references/ for detailed info**: Link to them rather than embedding large docs
- **Use scripts/ for deterministic operations**: Python/Bash for consistency

### Skills vs Commands

- **Skills** (recommended): Auto-trigger based on context, mirrored by bootstrap to `~/.claude/skills/` and `~/.codex/skills/`
- **Commands** (legacy): Slash commands like `/command-name`, defined in `~/.claude/commands/`

Most use cases should use skills. Commands are mainly for backward compatibility.

### Installing Skills

Skills in `~/code/dotfiles/claude-config/skills/` are symlinked by `bootstrap.sh` to both `~/.claude/skills/` and `~/.codex/skills/`.

To add a new skill:
1. Create it in `~/code/dotfiles/claude-config/skills/my-skill/`
2. Run `ln -sf ~/code/dotfiles/claude-config/skills/my-skill ~/.claude/skills/my-skill`
3. Run `ln -sf ~/code/dotfiles/claude-config/skills/my-skill ~/.codex/skills/my-skill`
4. Skills are loaded automatically on next Claude/Codex session

## MCP Gateway

Agents have access to `mcp__gateway__*` tools for capabilities beyond the built-in toolset.

**Available now**:
- **Context7** — library docs lookup (resolve library ID, then fetch docs by topic)
- **Playwright** — browser automation (also available directly via `mcp__plugin_playwright_playwright__*`)
- **20+ provisionable servers** — GitHub, Slack, Notion, etc. via `gateway_provision`

**Workflow**: `gateway_catalog_search` -> `gateway_describe` -> `gateway_invoke`

**Natural language**: `gateway_request_capability(query="...")` to find or provision tools.

**Debugging**: `gateway_list_pending` to check stuck requests, `gateway_cancel` to abort.

## Efficiency Skills (Auto-Triggered)

These skills auto-trigger based on context but knowing they exist helps you invoke them proactively:

- **Bash failures**: `/diagnose-bash-error` — decision tree for exit codes. STOP and diagnose before retrying.
- **Build commands**: `/validate-before-bash` — preflight checks before tsc, pytest, flutter build, cargo build
- **Search patterns**: `/smart-search` — ripgrep escaping rules, tool selection (Grep vs Glob vs Explore)
- **Spawning subagents**: `/task-contextualizer` — include file paths and architecture context in Task prompts
- **File editing**: `/safe-edit` — always Read before Edit; subagents must read independently
- **File reading**: `/file-read-cache` — don't re-read files you already have in context
- **Multi-file edits**: `/batch-verify` — complete all related edits, then verify once
- **Browser testing**: `/smart-screenshot` — use snapshot for actions, screenshot only for visual checks
- **Page load failures**: `/page-load-monitor` — diagnose after 2 failures, don't just retry
- **New project**: `/detect-environment` — one-pass tool detection
