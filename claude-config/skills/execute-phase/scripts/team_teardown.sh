#!/usr/bin/env bash
# team_teardown.sh — filesystem fallback for TeamDelete.
#
# Usage:
#     team_teardown.sh <team-name>
#
# Behavior:
#   - Removes ~/.claude/teams/<team-name>/ and ~/.claude/tasks/<team-name>/.
#   - Idempotent (no-op if dirs don't exist).
#   - Never fails (exit 0 always).
#
# Rationale (SKILL Lesson #5): "In-process teammates ignore shutdown_request.
# TeamDelete blocks on active members. If a teammate is backendType:
# 'in-process' and not acking shutdown, `rm -rf ~/.claude/teams/<team>` +
# `rm -rf ~/.claude/tasks/<team>` is the accepted tear-down path after the
# phase has verified green." The orchestrator should call TeamDelete first;
# fall back to this script when TeamDelete fails on active members.

set -uo pipefail

if [[ $# -ne 1 ]]; then
    echo "usage: team_teardown.sh <team-name>" >&2
    exit 2
fi

team="$1"
team_dir="$HOME/.claude/teams/$team"
task_dir="$HOME/.claude/tasks/$team"

rm -rf "$team_dir" "$task_dir"

echo "team_teardown: removed (or already absent): $team_dir $task_dir"
exit 0
