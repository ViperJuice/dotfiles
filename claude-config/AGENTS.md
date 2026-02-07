# Global Agent Instructions

See `~/.claude/skills/` for available skills.

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
   # Symlink to ~/.claude/skills/my-skill for testing
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

- **Skills** (recommended): Auto-trigger based on context, defined in `~/.claude/skills/`
- **Commands** (legacy): Slash commands like `/command-name`, defined in `~/.claude/commands/`

Most use cases should use skills. Commands are mainly for backward compatibility.

### Installing Skills

Skills in `~/code/dotfiles/claude-config/skills/` are symlinked to `~/.claude/skills/` by `bootstrap.sh`.

To add a new skill:
1. Create it in `~/code/dotfiles/claude-config/skills/my-skill/`
2. Run `ln -sf ~/code/dotfiles/claude-config/skills/my-skill ~/.claude/skills/my-skill`
3. Skills are loaded automatically on next Claude Code session

## MCP Gateway

Agents have access to `mcp__gateway__*` tools for capabilities beyond the built-in toolset. Use `gateway_catalog_search` to discover available tools, then `gateway_describe` and `gateway_invoke` to use them. Use `gateway_request_capability` for natural language capability matching.
