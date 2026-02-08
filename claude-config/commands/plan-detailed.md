---
description: Generate a detailed implementation plan with explicit file/method/class changes and reasons
allowed-tools: Bash(git:*), Bash(find:*), Bash(ls:*), Read, Glob, Grep, Task
---

# Detailed Implementation Plan

## Project Context

* Git status: !`git status --porcelain | head -20`
* Recent commits: !`git log --oneline -5 2>/dev/null`
* Project root: !`git rev-parse --show-toplevel 2>/dev/null || pwd`

## Task

$ARGUMENTS

If no task was provided above, use the preceding conversation context to determine what needs to be planned.

## Instructions

You are creating a detailed implementation plan. Follow these rules strictly:

### 1. Research First

Before proposing any changes, thoroughly explore the codebase:
- Search for existing functions, utilities, and patterns that can be reused
- Identify the files and modules involved in the task
- Understand the current architecture and conventions

### 2. Explicit Change Enumeration

For EVERY change, explicitly state:
- **File path**: Full path to the file being modified or created
- **Entity**: The specific model, class, method, function, table, column, or config being changed
- **Action**: Whether it is being added, modified, or deleted
- **Reason**: Why this change is necessary

Present changes as a structured list grouped by file, for example:

**`src/auth/login.py`** (modify)
- `LoginHandler.validate()` — modify — Add token expiration check (currently missing, causes stale sessions)
- `LoginHandler._refresh_token()` — add — Extract refresh logic from validate() for separation of concerns

### 3. Modification Over Creation

- **Always prefer modifying existing code** over creating new files or functions
- Search for broken, incomplete, or suboptimal code that should be fixed as part of this work
- Only create new files/functions when:
  - Separation of concerns genuinely requires it
  - A new feature has no existing home in the codebase
  - Existing code would become unwieldy with the additions

### 4. Scope Discipline

- Do NOT add features beyond what was requested
- Do NOT refactor surrounding code unless it is broken or directly blocks the task
- Do NOT add speculative error handling, comments, or type annotations to unchanged code

### 5. Output Format

Structure your plan as:

#### Summary
1-3 sentences on what this plan accomplishes.

#### Changes
Group by file. Each entry: entity, action (add/modify/delete), reason.

#### Dependencies & Order
Which changes must happen first. Note any blocking dependencies.

#### Verification
How to test that the implementation is correct (commands to run, behavior to check, edge cases).
