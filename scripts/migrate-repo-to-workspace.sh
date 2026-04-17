#!/bin/bash
# Move a repo from ~/code/<name> to /mnt/workspace/code/<name>, replacing the
# original with a symlink. Idempotent-ish — refuses to run if the source is
# already a symlink or if something has open file handles in the tree.
#
# Usage:  migrate-repo-to-workspace.sh <repo-name> [--force]
# Example: migrate-repo-to-workspace.sh onto-attentive-retrieval

set -euo pipefail

REPO_NAME="${1:?Usage: $0 <repo-name> [--force]}"
FORCE=0
[ "${2:-}" = "--force" ] && FORCE=1

SRC="$HOME/code/$REPO_NAME"
DST="/mnt/workspace/code/$REPO_NAME"

# --- Preconditions ---
[ -d "/mnt/workspace" ] || { echo "ERROR: /mnt/workspace not mounted"; exit 1; }
[ -e "$SRC" ] || { echo "ERROR: $SRC does not exist"; exit 1; }
[ -L "$SRC" ] && { echo "ERROR: $SRC is already a symlink"; exit 1; }

# --- Safety: refuse if processes have files open under $SRC ---
if [ "$FORCE" -eq 0 ]; then
    if command -v lsof >/dev/null 2>&1; then
        open_procs=$(lsof +D "$SRC" 2>/dev/null | tail -n +2 | wc -l)
        if [ "$open_procs" -gt 0 ]; then
            echo "ERROR: $open_procs process(es) have files open under $SRC."
            echo "Active processes (lsof +D summary):"
            lsof +D "$SRC" 2>/dev/null | awk 'NR>1 {print "  " $1 " (pid " $2 ")"}' | sort -u | head -10
            echo "Close them, or pass --force if you know what you're doing."
            exit 1
        fi
    fi
fi

# --- Warn about uncommitted/dirty git state ---
if [ -d "$SRC/.git" ]; then
    dirty=$(cd "$SRC" && git status --porcelain 2>/dev/null | wc -l)
    if [ "$dirty" -gt 0 ]; then
        echo "NOTE: $SRC has $dirty uncommitted change(s). Migration is still safe"
        echo "(rsync preserves everything), but you should be aware."
        if [ "$FORCE" -eq 0 ]; then
            read -p "Continue? (y/N) " ans
            [[ "${ans:-n}" =~ ^[Yy] ]] || exit 1
        fi
    fi
fi

mkdir -p /mnt/workspace/code

echo "=== Copy $SRC -> $DST ==="
rsync -a --delete --info=stats1 "$SRC/" "$DST/"

echo "=== Verify (rsync dry-run should show no diffs) ==="
diff_lines=$(rsync -an --delete --itemize-changes "$SRC/" "$DST/" | grep -cE '^[>c<*]')
if [ "$diff_lines" -ne 0 ]; then
    echo "ERROR: rsync verify found $diff_lines differences. Aborting before swap."
    echo "Leaving $DST in place for inspection; $SRC untouched."
    exit 1
fi

echo "=== Swap original for symlink ==="
STASH="${SRC}.PRE-MIGRATE-$(date +%s)"
mv "$SRC" "$STASH"
ln -s "$DST" "$SRC"

echo ""
echo "Done. New layout:"
ls -la "$SRC"
echo ""
echo "Rollback, if needed (kept for safety):"
echo "  rm '$SRC' && mv '$STASH' '$SRC' && rm -rf '$DST'"
echo ""
echo "Once confirmed healthy (days later):"
echo "  rm -rf '$STASH'"
