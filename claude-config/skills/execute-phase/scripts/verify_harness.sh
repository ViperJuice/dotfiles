#!/usr/bin/env bash
# verify_harness.sh — pre-flight capability check for execute-phase.
#
# Usage:
#     verify_harness.sh [merge-target]
#
#     merge-target    Defaults to 'main'.
#
# Checks (all run; exit code reflects aggregate — non-zero if any FAIL):
#   (1) `git` + `git worktree` available
#   (2) Running inside a git work tree (`rev-parse --show-toplevel` succeeds)
#   (3) Merge target branch exists locally
#   (4) Working tree is clean (no uncommitted changes)
#   (5) `.gitignore` mentions worktree paths — WARN only
#
# Does NOT exercise EnterWorktree itself — that's a Claude tool, not a CLI.
# The SKILL's Step 2 tells the LLM to follow this script with a throwaway-
# teammate probe that calls EnterWorktree and reports whether the tool is
# available in the teammate's registry.

set -uo pipefail

target="${1:-main}"

errors=0
warnings=0

pass() { echo "verify_harness: PASS — $*"; }
warn() { echo "verify_harness: WARN — $*" >&2; warnings=$((warnings + 1)); }
fail() { echo "verify_harness: FAIL — $*" >&2; errors=$((errors + 1)); }

# (1) git + worktree subcommand
if ! command -v git >/dev/null 2>&1; then
    fail "(1) git not found on PATH"
elif ! git worktree list >/dev/null 2>&1; then
    fail "(1) 'git worktree' subcommand unavailable"
else
    pass "(1) git + git-worktree available"
fi

# (2) inside a git work tree
toplevel=""
if toplevel="$(git rev-parse --show-toplevel 2>/dev/null)"; then
    pass "(2) inside git work tree: $toplevel"
else
    fail "(2) not inside a git work tree"
fi

# (3) merge target branch exists locally
if git show-ref --verify --quiet "refs/heads/$target"; then
    pass "(3) merge target '$target' exists locally"
else
    fail "(3) merge target '$target' does not exist locally (try: git fetch origin $target:$target)"
fi

# (4) working tree clean
dirty_count=$(git status --porcelain 2>/dev/null | wc -l)
if [[ "$dirty_count" -eq 0 ]]; then
    pass "(4) working tree clean"
else
    fail "(4) working tree has $dirty_count uncommitted change(s); commit or stash before /execute-phase"
fi

# (5) .gitignore covers worktree paths — WARN only, not a hard-fail.
gitignore="$toplevel/.gitignore"
if [[ -f "$gitignore" ]]; then
    if grep -qE '^(\.worktrees/?|\.claude/worktrees/?)' "$gitignore"; then
        pass "(5) .gitignore covers worktree paths"
    else
        warn "(5) .gitignore does not list '.worktrees/' or '.claude/worktrees/'; execute-phase will append on first run"
    fi
else
    warn "(5) no .gitignore at $gitignore"
fi

echo "verify_harness: summary — $errors error(s), $warnings warning(s)"
if [[ "$errors" -gt 0 ]]; then
    exit 1
fi
exit 0
