#!/bin/bash
# Sync documentation from all repos to Obsidian vault
# Creates symlinks organized by repo and by type

# Defaults
CODE_DIR="${CODE_DIR:-$HOME/code}"
OBSIDIAN_DIR="${OBSIDIAN_DIR:-$HOME/code/obsidian-dev-docs}"
EXCLUDE_REPOS_ARRAY=(obsidian-dev-docs)

# Parse args
while [[ $# -gt 0 ]]; do
    case $1 in
        --code-dir) CODE_DIR="$2"; shift 2 ;;
        --obsidian-dir) OBSIDIAN_DIR="$2"; shift 2 ;;
        --quiet) QUIET=1; shift ;;
        *) echo "Unknown option: $1"; exit 1 ;;
    esac
done

log() {
    [[ -z "$QUIET" ]] && echo "$@"
}

# Track changes for summary
ADDED_REPOS=()
ADDED_DOCS=()
ADDED_CLAUDE=()
ADDED_MD=()
REMOVED=()

# Clean up broken symlinks first
cleanup_broken_links() {
    local dir="$1"
    if [[ -d "$dir" ]]; then
        find "$dir" -type l ! -exec test -e {} \; -print 2>/dev/null | while read -r broken; do
            rm -f "$broken"
            REMOVED+=("$broken")
        done
        # Remove empty repo directories (but not the by-type structure dirs)
        find "$dir" -mindepth 2 -type d -empty -delete 2>/dev/null || true
    fi
}

cleanup_broken_links "$OBSIDIAN_DIR/repos"
cleanup_broken_links "$OBSIDIAN_DIR/by-type"

# Create directory structure (after cleanup to ensure they exist)
mkdir -p "$OBSIDIAN_DIR/repos"
mkdir -p "$OBSIDIAN_DIR/by-type/docs"
mkdir -p "$OBSIDIAN_DIR/by-type/claude-configs"
mkdir -p "$OBSIDIAN_DIR/by-type/readmes"

# Scan for repos with docs or .claude
for repo_path in "$CODE_DIR"/*/; do
    # Normalize path (remove trailing slash)
    repo_path="${repo_path%/}"
    repo_name=$(basename "$repo_path")

    # Skip excluded repos (exact match, not substring)
    skip_repo=false
    for exclude in "${EXCLUDE_REPOS_ARRAY[@]}"; do
        if [[ "$repo_name" == "$exclude" ]]; then
            skip_repo=true
            break
        fi
    done
    $skip_repo && continue

    # Documentation directories to look for
    DOC_DIRS=("docs" "ai-docs" "specs" "plans" "architecture" ".claude" ".cursor" ".gemini")

    found_dirs=()
    has_md_files=false

    # Check for documentation directories
    for dir in "${DOC_DIRS[@]}"; do
        if [[ -d "$repo_path/$dir" ]]; then
            found_dirs+=("$dir")
        fi
    done

    # Check for root-level markdown files
    if ls "$repo_path"/*.md &>/dev/null; then
        has_md_files=true
    fi

    # Skip repos with no documentation
    if [[ ${#found_dirs[@]} -eq 0 ]] && ! $has_md_files; then
        continue
    fi

    # Create repo directory in obsidian
    repo_obs_dir="$OBSIDIAN_DIR/repos/$repo_name"
    if [[ ! -d "$repo_obs_dir" ]]; then
        mkdir -p "$repo_obs_dir"
        ADDED_REPOS+=("$repo_name")
    fi

    # Create symlinks for each found documentation directory
    for dir in "${found_dirs[@]}"; do
        # Clean name for symlink (remove leading dot)
        link_name="${dir#.}"

        dir_link="$repo_obs_dir/$link_name"
        if [[ ! -L "$dir_link" ]]; then
            ln -sf "$repo_path/$dir" "$dir_link"

            # Track what type was added
            case "$dir" in
                docs) ADDED_DOCS+=("$repo_name") ;;
                .claude) ADDED_CLAUDE+=("$repo_name") ;;
            esac
        fi

        # by-type symlinks
        case "$dir" in
            docs)
                bytype_link="$OBSIDIAN_DIR/by-type/docs/$repo_name"
                ;;
            .claude)
                bytype_link="$OBSIDIAN_DIR/by-type/claude-configs/$repo_name"
                ;;
            ai-docs)
                mkdir -p "$OBSIDIAN_DIR/by-type/ai-docs"
                bytype_link="$OBSIDIAN_DIR/by-type/ai-docs/$repo_name"
                ;;
            specs)
                mkdir -p "$OBSIDIAN_DIR/by-type/specs"
                bytype_link="$OBSIDIAN_DIR/by-type/specs/$repo_name"
                ;;
            plans)
                mkdir -p "$OBSIDIAN_DIR/by-type/plans"
                bytype_link="$OBSIDIAN_DIR/by-type/plans/$repo_name"
                ;;
            architecture)
                mkdir -p "$OBSIDIAN_DIR/by-type/architecture"
                bytype_link="$OBSIDIAN_DIR/by-type/architecture/$repo_name"
                ;;
            .cursor)
                mkdir -p "$OBSIDIAN_DIR/by-type/cursor"
                bytype_link="$OBSIDIAN_DIR/by-type/cursor/$repo_name"
                ;;
            .gemini)
                mkdir -p "$OBSIDIAN_DIR/by-type/gemini"
                bytype_link="$OBSIDIAN_DIR/by-type/gemini/$repo_name"
                ;;
            *)
                bytype_link=""
                ;;
        esac

        if [[ -n "$bytype_link" && ! -L "$bytype_link" ]]; then
            ln -sf "$repo_path/$dir" "$bytype_link"
        fi
    done

    # Create symlinks for root-level markdown files
    if $has_md_files; then
        md_added=false
        for md_file in "$repo_path"/*.md; do
            [[ -f "$md_file" ]] || continue
            md_name=$(basename "$md_file")

            # Symlink into repo folder (prefixed with repo name for uniqueness in Obsidian)
            md_link="$repo_obs_dir/$md_name"
            if [[ ! -L "$md_link" ]]; then
                ln -sf "$md_file" "$md_link"
                md_added=true
            fi
        done

        # For by-type/readmes, symlink just README.md (most important)
        if [[ -f "$repo_path/README.md" ]]; then
            readme_link="$OBSIDIAN_DIR/by-type/readmes/${repo_name}.md"
            if [[ ! -L "$readme_link" ]]; then
                ln -sf "$repo_path/README.md" "$readme_link"
            fi
        fi

        $md_added && ADDED_MD+=("$repo_name")
    fi
done

# Summary
if [[ -z "$QUIET" ]]; then
    if [[ ${#ADDED_REPOS[@]} -gt 0 || ${#ADDED_DOCS[@]} -gt 0 || ${#ADDED_CLAUDE[@]} -gt 0 || ${#ADDED_MD[@]} -gt 0 || ${#REMOVED[@]} -gt 0 ]]; then
        echo "Obsidian docs sync complete:"
        [[ ${#ADDED_REPOS[@]} -gt 0 ]] && echo "  + Added repos: ${ADDED_REPOS[*]}"
        [[ ${#ADDED_DOCS[@]} -gt 0 ]] && echo "  + Linked docs/: ${ADDED_DOCS[*]}"
        [[ ${#ADDED_CLAUDE[@]} -gt 0 ]] && echo "  + Linked .claude/: ${ADDED_CLAUDE[*]}"
        [[ ${#ADDED_MD[@]} -gt 0 ]] && echo "  + Linked .md files: ${ADDED_MD[*]}"
        [[ ${#REMOVED[@]} -gt 0 ]] && echo "  - Removed broken links: ${#REMOVED[@]}"
    else
        echo "Obsidian docs sync: no changes"
    fi
fi

exit 0
