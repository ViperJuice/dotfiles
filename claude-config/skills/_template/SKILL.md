---
name: skill-identifier
description: When to trigger this skill - be specific about the scenarios where Claude should use it
---

# Skill Name

Brief overview of what this skill provides.

## When to Use

Specific triggers that should activate this skill:
- User asks to [do X]
- User mentions [keyword Y]
- User wants to [accomplish Z]

## Instructions

Clear, concise instructions for Claude to follow when using this skill.

### Step 1: [Action]

Detailed guidance on the first step.

### Step 2: [Action]

Detailed guidance on the second step.

## Examples

```bash
# Example command or code snippet
```

## Notes

- **references/**: Place detailed documentation here (loaded only when needed)
- **scripts/**: Place reusable scripts here for deterministic operations
- **assets/**: Place templates, config files, or other resources here

## Important Principles

1. **Keep SKILL.md concise** - You share the context window with conversation
2. **Description is critical** - Determines when this auto-triggers
3. **Use references/ for details** - Link to them rather than duplicating content
4. **Scripts for consistency** - Python/Bash for operations that need exact behavior
