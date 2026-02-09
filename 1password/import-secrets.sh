#!/bin/bash
# Import secrets from remote .env files into 1Password
# Pulls from Tailscale-connected machines and stores in a "Development" vault
#
# Usage: ./import-secrets.sh [--dry-run]
#
# Requires: op CLI signed in, tailscale connected

set -e

DRY_RUN=false
[[ "$1" == "--dry-run" ]] && DRY_RUN=true

VAULT="Development"

# Check prerequisites
if ! command -v op &>/dev/null; then
    echo "Error: 1Password CLI (op) not installed"
    exit 1
fi

if ! op vault list &>/dev/null 2>&1; then
    echo "Error: Not signed in to 1Password. Run: eval \$(op signin)"
    exit 1
fi

# Create vault if it doesn't exist
if ! op vault get "$VAULT" &>/dev/null 2>&1; then
    echo "Creating vault: $VAULT"
    if [ "$DRY_RUN" = false ]; then
        op vault create "$VAULT"
    else
        echo "  [dry-run] Would create vault: $VAULT"
    fi
fi

# Track unique secrets (dedup across machines)
declare -A SECRETS

# Parse .env file contents and extract key=value pairs (skip comments/empty/refs)
parse_env() {
    local content="$1"
    while IFS= read -r line; do
        # Skip comments, empty lines, and variable references
        [[ "$line" =~ ^[[:space:]]*# ]] && continue
        [[ -z "$line" ]] && continue
        [[ "$line" =~ \$\{ ]] && continue
        [[ "$line" == *"=placeholder"* ]] && continue
        [[ "$line" == *"=your_"* ]] && continue

        # Extract key=value
        if [[ "$line" =~ ^([A-Za-z_][A-Za-z0-9_]*)=(.+)$ ]]; then
            local key="${BASH_REMATCH[1]}"
            local value="${BASH_REMATCH[2]}"
            # Skip non-secret config values
            case "$key" in
                *_MODEL|*_BASE_URL|*_HOST|*_DIR|*_REPO|*_PROVIDER|*_TIER|*_RETRIES|*_REPLY|*_AUTORESPOND|GITHUB_REPOSITORY|PLATFORM)
                    continue
                    ;;
                BAML_*_API_KEY)
                    # Skip BAML duplicates — these reference the same underlying keys
                    continue
                    ;;
            esac
            SECRETS[$key]="$value"
        fi
    done <<< "$content"
}

echo "Collecting secrets from remote machines..."
echo ""

# --- claw ---
if ssh -o ConnectTimeout=5 -o BatchMode=yes claw 'true' &>/dev/null; then
    echo "📡 claw (cloud dev server)"

    # ai-dev-kit/.env
    content=$(ssh claw 'cat /home/clawd/code/ai-dev-kit/.env 2>/dev/null' 2>/dev/null) || true
    if [ -n "$content" ]; then
        echo "  Reading ai-dev-kit/.env"
        parse_env "$content"
    fi

    # consiliency-orchestrator/.env
    content=$(ssh claw 'cat /home/clawd/code/consiliency-orchestrator/.env 2>/dev/null' 2>/dev/null) || true
    if [ -n "$content" ]; then
        echo "  Reading consiliency-orchestrator/.env"
        parse_env "$content"
    fi

    # code-flow-template/.env.local
    content=$(ssh claw 'cat /home/clawd/code/code-flow-template/.env.local 2>/dev/null' 2>/dev/null) || true
    if [ -n "$content" ]; then
        echo "  Reading code-flow-template/.env.local"
        parse_env "$content"
    fi
else
    echo "⚠ claw not reachable — skipping"
fi

echo ""

# --- leno (WSL) ---
# leno runs Windows; SSH may need to go through WSL explicitly
# Uncomment and adjust if SSH to WSL is configured:
# if tailscale ping leno --timeout 3s &>/dev/null 2>&1; then
#     echo "📡 leno (WSL)"
#     content=$(ssh leno 'wsl bash -c "cat ~/code/*/.env 2>/dev/null"' 2>/dev/null) || true
#     if [ -n "$content" ]; then
#         parse_env "$content"
#     fi
# fi

# --- Summary and import ---
echo "Found ${#SECRETS[@]} unique secrets:"
echo ""

for key in $(echo "${!SECRETS[@]}" | tr ' ' '\n' | sort); do
    value="${SECRETS[$key]}"
    # Mask value for display
    masked="${value:0:8}...${value: -4}"
    echo "  $key = $masked"
done

echo ""

if [ "$DRY_RUN" = true ]; then
    echo "[dry-run] Would create items in 1Password vault '$VAULT'"
    exit 0
fi

read -p "Import these into 1Password vault '$VAULT'? [y/N] " confirm
[[ "$confirm" != [yY]* ]] && { echo "Aborted."; exit 0; }

echo ""
echo "Importing..."

for key in $(echo "${!SECRETS[@]}" | tr ' ' '\n' | sort); do
    value="${SECRETS[$key]}"

    # Determine a category/title based on key name
    case "$key" in
        ANTHROPIC_*)  title="Anthropic" ;;
        CEREBRAS_*)   title="Cerebras" ;;
        GROQ_*)       title="Groq" ;;
        BRIGHTDATA_*) title="BrightData" ;;
        OLLAMA_*)     title="Ollama" ;;
        *)            title="Dev Secrets" ;;
    esac

    # Check if item already exists
    existing=$(op item list --vault "$VAULT" --format json 2>/dev/null | \
        python3 -c "import sys,json; items=json.load(sys.stdin); print(next((i['id'] for i in items if i['title']=='$title'), ''))" 2>/dev/null) || true

    if [ -n "$existing" ]; then
        # Update existing item — add/update the field
        op item edit "$existing" --vault "$VAULT" "$key=$value" >/dev/null 2>&1 && \
            echo "  ✓ Updated $title.$key" || \
            echo "  ⚠ Failed to update $title.$key"
    else
        # Create new item
        op item create --vault "$VAULT" --category "API Credential" \
            --title "$title" "$key=$value" >/dev/null 2>&1 && \
            echo "  ✓ Created $title with $key" || \
            echo "  ⚠ Failed to create $title"
    fi
done

echo ""
echo "✅ Import complete!"
echo ""
echo "Use secrets in your shell:"
echo "  export ANTHROPIC_API_KEY=\$(op read 'op://$VAULT/Anthropic/ANTHROPIC_API_KEY')"
echo ""
echo "Or use op run to inject into a command:"
echo "  op run --env-file=.env.op -- your-command"
