#!/usr/bin/env bash
# parent_tree_leakage_check.sh — detect when a teammate's filesystem edits
# escaped its worktree into the parent checkout (Lesson #10 defense).
#
# Usage:
#     parent_tree_leakage_check.sh <lane-id> <owned-globs-file>
#
#     <lane-id>            Informational only; echoed into stdout for
#                          orchestrator logging.
#     <owned-globs-file>   File with one glob pattern per line; these are
#                          the lane's `Owned files` from the plan doc.
#                          Passing /dev/null is valid (treat empty globs
#                          as "nothing is owned" → any dirty file counts
#                          as unrelated).
#
# Behavior: emits EXACTLY one token on stdout, exit 0 always.
#
#   CLEAN
#     - Working tree has no uncommitted changes. No leakage.
#
#   LEAKAGE_DETECTED
#     - Working tree has dirty files AND at least one matches the lane's
#       owned globs. The teammate wrote into the parent checkout rather
#       than the worktree; orchestrator should stash or abort before merge.
#
#   UNRELATED_DIRTY_TREE
#     - Working tree has dirty files but NONE match the lane's owned
#       globs. Probably other orchestrator-level changes; caller decides.
#
# Implementation notes:
#   - Runs from the parent checkout (the cwd of the orchestrator's git
#     context, not the lane's worktree).
#   - `git status --porcelain` output: `XY <path>` where X/Y are status
#     codes; we parse the path by stripping the first 3 chars.

set -uo pipefail

if [[ $# -ne 2 ]]; then
    echo "usage: parent_tree_leakage_check.sh <lane-id> <owned-globs-file>" >&2
    exit 2
fi

lane_id="$1"
globs_path="$2"

# Load owned globs.
globs=()
if [[ -r "$globs_path" && "$globs_path" != "/dev/null" ]]; then
    while IFS= read -r line; do
        line="${line%%#*}"
        line="$(echo -n "$line" | xargs || true)"
        [[ -z "$line" ]] && continue
        globs+=("$line")
    done < "$globs_path"
fi

# Enumerate dirty paths from the parent checkout.
dirty_paths=()
while IFS= read -r line; do
    [[ -z "$line" ]] && continue
    # Status code (first 2 chars) + a space, then the path. Renames use
    # "R  old -> new"; we take the NEW path.
    path="${line:3}"
    if [[ "$path" == *" -> "* ]]; then
        path="${path#* -> }"
    fi
    # Strip surrounding quotes git adds for paths with spaces.
    path="${path#\"}"
    path="${path%\"}"
    dirty_paths+=("$path")
done < <(git status --porcelain 2>/dev/null)

if [[ ${#dirty_paths[@]} -eq 0 ]]; then
    echo "CLEAN"
    exit 0
fi

# Test each dirty path against the lane's globs.
is_owned() {
    local path="$1"
    local pat
    for pat in "${globs[@]+"${globs[@]}"}"; do
        # shellcheck disable=SC2053
        if [[ "$path" == $pat ]]; then
            return 0
        fi
    done
    return 1
}

leakage=false
for p in "${dirty_paths[@]}"; do
    if is_owned "$p"; then
        leakage=true
        echo "parent_tree_leakage_check: $lane_id — dirty path $p matches owned globs" >&2
    fi
done

if [[ "$leakage" == "true" ]]; then
    echo "LEAKAGE_DETECTED"
    exit 0
fi
echo "UNRELATED_DIRTY_TREE"
exit 0
