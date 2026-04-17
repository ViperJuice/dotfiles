#!/bin/bash
# Move a repo from ~/code/<name> to /mnt/workspace/code/<name> and bind-mount
# the workspace location back at the original path. Using a bind mount (not a
# symlink) preserves getcwd() / process.cwd() so Claude Code / Codex / opencode
# session histories keyed on ~/code/<name> continue to resolve.
#
# Side effects:
#   - copies SRC -> /mnt/workspace/code/<name>
#   - stashes original as SRC.PRE-MIGRATE-<timestamp>
#   - mkdirs an empty SRC and `sudo mount --bind` the workspace location there
#   - appends an fstab entry (bind, nofail, x-systemd.requires-mounts-for)
#
# Usage:  migrate-repo-to-workspace.sh <repo-name> [--force]

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
mountpoint -q "$SRC" && { echo "ERROR: $SRC is already a mount point"; exit 1; }

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
            if [ -t 0 ]; then
                read -p "Continue? (y/N) " ans
                [[ "${ans:-n}" =~ ^[Yy] ]] || exit 1
            else
                echo "ERROR: uncommitted changes and stdin is not a TTY — refusing to prompt."
                echo "Re-run with --force to migrate anyway (rsync preserves the dirty state)."
                exit 1
            fi
        fi
    fi
fi

mkdir -p /mnt/workspace/code

# Warn if SRC has nested mounts (sshfs, bind, NFS) — -x skips them but caller should know
nested_mounts=$(mount | awk -v src="$SRC/" '$3 ~ "^"src {print "  " $3}' | head)
if [ -n "$nested_mounts" ]; then
    echo "NOTE: nested mount(s) inside $SRC will be skipped (rsync -x):"
    echo "$nested_mounts"
    echo "Re-mount them manually at the new bind-mount location if needed."
fi

echo "=== Copy $SRC -> $DST ==="
rsync -ax --delete --info=stats1 "$SRC/" "$DST/"

echo "=== Verify (rsync dry-run should show no diffs) ==="
# grep -c returns 1 when no matches; pipe to || true so set -o pipefail doesn't kill us on the success path
diff_lines=$(rsync -an --delete --itemize-changes "$SRC/" "$DST/" | grep -cE '^[>c<*]' || true)
if [ "$diff_lines" -ne 0 ]; then
    echo "ERROR: rsync verify found $diff_lines differences. Aborting before swap."
    echo "Leaving $DST in place for inspection; $SRC untouched."
    exit 1
fi

echo "=== Swap original for bind mount ==="
STASH="${SRC}.PRE-MIGRATE-$(date +%s)"
mv "$SRC" "$STASH"
mkdir "$SRC"
sudo mount --bind "$DST" "$SRC"

echo "=== Persist via /etc/fstab (idempotent) ==="
FSTAB_LINE="$DST  $SRC  none  bind,nofail,x-systemd.requires-mounts-for=/mnt/HC_Volume_105438154  0  0"
if ! grep -qF "$DST  $SRC" /etc/fstab; then
    echo "$FSTAB_LINE" | sudo tee -a /etc/fstab >/dev/null
    echo "  added fstab entry"
else
    echo "  fstab entry already present"
fi

echo ""
echo "Done. New layout:"
mount | grep " on $SRC " || echo "(mount not visible?)"
echo ""
echo "Rollback, if needed (kept for safety):"
echo "  sudo umount '$SRC' && sudo sed -i '\\|$DST  $SRC|d' /etc/fstab && rmdir '$SRC' && mv '$STASH' '$SRC' && rm -rf '$DST'"
echo ""
echo "Once confirmed healthy (usually minutes is enough — bind mount is low-risk):"
echo "  rm -rf '$STASH'"
