---
name: task-contextualizer
description: "Guide for preparing rich context when spawning subagent tasks. Use before creating any Task tool call, especially for Explore or general-purpose subagents. Provides templates for task prompts that include necessary file paths, architecture context, and scope boundaries. Prevents subagent context starvation (84% of subagent sessions waste calls rediscovering project structure)."
---

# Task Contextualizer

## Overview

A subagent spawned with "fix the bug in pageContext.ts" will spend 10-15 Read calls discovering the file structure before it can start. A subagent spawned with the same task PLUS 5 key file paths and architecture notes goes straight to the fix — a 40-50% reduction in wasted calls.

Subagents do NOT inherit parent context. They start fresh. Every file you've read, every search result you've seen — the subagent knows none of it.

## Mandatory Checklist

Before EVERY Task tool call, verify:

- [ ] **File paths**: Listed the specific files the subagent needs to read or modify
- [ ] **Architecture context**: Explained how the relevant module fits into the larger system (1-2 sentences)
- [ ] **Scope boundary**: Told the subagent what NOT to touch
- [ ] **Expected output**: Specified what the subagent should produce (file changes, report, answer)
- [ ] **Related files**: Mentioned test files, config files, type definitions

## Bad vs Good

**BAD** (forces subagent to discover everything):
```
Fix the TypeScript error in the chat service
```

**GOOD** (subagent can start working immediately):
```
Fix the TypeScript error in /src/services/chatService.ts.

Error: "Property 'messageId' does not exist on type 'ChatEvent'" at line 142.

Related files:
- /src/types/chat.ts — ChatEvent and ChatMessage type definitions
- /src/services/apiClient.ts — base service class that chatService extends
- /tests/services/chatService.test.ts — existing tests

Architecture: chatService extends BaseApiService and handles WebSocket
messages. ChatEvent is the raw event type; ChatMessage is the processed type.

Scope: Only modify chatService.ts and chat.ts. Do not change apiClient.ts.
```

## Templates by Task Type

### Bug Fix
Include: file path + exact error message + related type/config files + test file

### New Feature
Include: example files showing the pattern to follow + target directory + naming/style conventions

### Research / Explore
Include: known file paths to start from + specific questions to answer + what you already know (so the agent doesn't re-discover it)

### Refactor
Include: all files to change + the target pattern + constraints on what must stay the same

## Key Insight for Explore Subagents

Explore agents are read-only — they can't edit files. But they spend the MOST on context discovery because they're often asked broad questions. Always give them:
1. Specific file paths to start from (not "find where X is")
2. Specific questions to answer (not "understand module X")
3. What you already know (so they don't re-discover it)

## Resources

### references/
Full copy-paste templates with placeholders for each task type. See `references/task-templates.md` for ready-to-use templates.
