# Global Agent Instructions

See `~/.claude/skills/` and `~/.codex/skills/` for available skills.

## Workspace volume (when `/mnt/workspace` exists)

**Our pipelines use git worktrees almost exclusively.** On any host where `/mnt/workspace` exists, worktrees and other heavy/temporary work MUST go there, not on the root disk.

**Rules — always follow when `/mnt/workspace` exists:**

- **Worktrees** — create as `git worktree add /mnt/workspace/worktrees/<project>-<branch> <branch>`. Never create worktrees next to the repo (`../repo-branch`) — root disk is small, workspace is 500G+. This applies to every worktree you create, including transient ones for parallel pipelines.
- **Large temporary data** — model downloads, datasets, build artifacts over ~1G. Route them into `/mnt/workspace/` subdirs rather than `$HOME` or `/tmp`.
- **Build caches (transparent)** — you do NOT need to manage these yourself. `CARGO_TARGET_DIR`, `~/.npm`, `~/.cache/uv`, `~/.cache/pnpm`, `~/.local/share/pnpm`, `~/.cargo/registry` already redirect onto the workspace volume via env var and symlinks. Normal `cargo build`, `pnpm install`, `uv sync`, `npm install` work unchanged.

**How to check:** `[ -d /mnt/workspace ]`. If it doesn't exist (display, ai, macmini, win-wsl), treat this section as inapplicable and use the repo-local conventions.

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

## Agent Architecture

The dotfiles repo is the single source of truth for all agent definitions. **Never edit agents in their native machine locations** (`~/.claude/agents/`, `~/.config/opencode/agents/`, etc.) — always edit in `~/code/dotfiles/` and run `./bootstrap.sh`.

### Source locations

| What | Source in dotfiles | Deployed to |
|------|-------------------|-------------|
| Shared agents | `shared/agents/<name>/` | Both Claude + OpenCode (assembled) |
| Claude-only agents | `claude-config/agents/*.md` | `~/.claude/agents/` (symlinked) |
| OpenCode-only agents | `opencode-config/agents/*.md` | `~/.config/opencode/agents/` (symlinked) |
| Antigravity skills | `antigravity-config/skills/` | `~/.gemini/antigravity/skills/` (symlinked) |
| PI skills | `pi-config/skills/` | `~/.pi/agent/skills/` (symlinked) |

### Shared agents (`shared/agents/<name>/`)

Each shared agent has a directory with a shared prompt and per-tool metadata:

```
shared/agents/yolo/
├── prompt.md          # Prompt body (shared)
├── claude.json        # Claude Code: name, description, permissionMode
└── opencode.json      # OpenCode: description, mode (primary/subagent/all)
```

Bootstrap deploys each to the tool's native format:
- **Claude Code**: JSON -> YAML front matter + prompt -> `~/.claude/agents/<name>.md`
- **OpenCode**: JSON injected into `opencode.json` config, prompt symlinked via `{file:~/.config/opencode/prompts/<name>.md}`

### Claude Code subagent fields

```yaml
---
name: agent-name
description: When to auto-delegate to this agent (with examples)
permissionMode: bypassPermissions  # or default
model: claude-sonnet-4-5-20250514  # optional override
maxTurns: 50                       # optional
tools:                             # optional allowlist
  - Read
  - Edit
  - Bash
---
```

### OpenCode agent fields

```json
{
  "description": "When to use this agent",
  "mode": "all",           // "primary" | "subagent" | "all"
  "model": "...",           // optional model override
  "temperature": 0.7,      // optional
  "tools": {},              // optional tool allow/deny
  "prompt": "{file:path}"  // injected by bootstrap
}
```

### Fallback behavior

- **OpenCode** reads `~/.claude/CLAUDE.md` and `~/.claude/skills/` automatically (disable with `OPENCODE_DISABLE_CLAUDE_CODE=1`)
- **Antigravity** reads `~/.gemini/GEMINI.md` (generated from `shared/instructions/core.md`)
- **PI** reads `~/.pi/agent/AGENTS.md` (generated from `shared/instructions/core.md`)
- Skills in `claude-config/skills/` are shared to Claude Code, Codex, and Antigravity

## Multi-Tool Support

The bootstrap script configures all tools from shared sources:
- **Claude Code**: Settings, agents, commands, skills via `~/.claude/`
- **OpenCode**: MCP config, shared agents, commands via `~/.config/opencode/`
- **Antigravity**: Skills (shared from Claude) + MCP via `~/.gemini/antigravity/`
- **Gemini CLI**: Instructions via `~/.gemini/GEMINI.md`, MCP gateway
- **Cursor IDE**: Rules via `~/.cursor/rules/`, MCP gateway
- **PI**: Instructions via `~/.pi/agent/AGENTS.md`, skills
- **Codex**: Skills via `~/.codex/skills/`

## MCP Gateway

Agents have access to `mcp__pmcp__*` tools for capabilities beyond the built-in toolset.

**Available now**:
- **Context7** — library docs lookup (resolve library ID, then fetch docs by topic)
- **Playwright** — browser automation (`playwright::*` tools via gateway)
- **20+ provisionable servers** — GitHub, Slack, Notion, etc. via `pmcp_provision`

**Workflow**: `pmcp_catalog_search` -> `pmcp_describe` -> `pmcp_invoke`

**Natural language**: `pmcp_request_capability(query="...")` to find or provision tools.

**Debugging**: `pmcp_list_pending` to check stuck requests, `pmcp_cancel` to abort.

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
