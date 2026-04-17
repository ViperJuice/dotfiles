# Global Claude Instructions

See AGENTS.md for agent-specific instructions.

## Git worktrees — location rule (read first)

**Our pipelines use `git worktree` almost exclusively.** If `/mnt/workspace` exists on the current host (e.g., claw), create every worktree under `/mnt/workspace/worktrees/<project>-<branch>` — NEVER next to the repo on root. On hosts without `/mnt/workspace`, use repo siblings as usual. Build caches (cargo/pnpm/npm/uv) already redirect transparently — no special handling needed. See `AGENTS.md` → "Workspace volume" for full rules.

## Interactive Testing Workflow

**CRITICAL**: Always test UI features interactively in the browser before marking them complete.

Default to **Playwright** via the PMCP gateway for all browser automation. Use `pmcp_invoke` with `playwright::*` tool IDs.

`claude-in-chrome` tools are only available in EZBidPro sessions (disabled globally) — use only when Chrome extension contexts are needed.

For full details on tool selection, CDP connections, authenticated sessions, and infrastructure: invoke `/browser-automation`.

## MCP Gateway (PMCP)

An MCP gateway is available via tools prefixed with `mcp__pmcp__`. Before reaching for Bash workarounds or telling the user something isn't possible, check whether the gateway has a tool for it.

**Available servers**: Playwright (browser automation), Context7 (library docs), browser-use, and on-demand provisioned servers.

**Discovery workflow**: `pmcp_catalog_search` -> `pmcp_describe` -> `pmcp_invoke`

**Library docs (Context7)**:
1. `pmcp_invoke(tool_id="context7::resolve-library-id", arguments={"libraryName": "react"})`
2. `pmcp_invoke(tool_id="context7::get-library-docs", arguments={"context7CompatibleLibraryID": "/facebook/react", "topic": "hooks"})`

**Natural language discovery**: `pmcp_request_capability(query="I need to search Slack messages")` — matches to installed tools or provisions new servers.

**Operational tools** (for debugging hangs or checking status):
- `pmcp_health` — server status and tool counts
- `pmcp_list_pending` — in-flight requests with elapsed time
- `pmcp_cancel(request_id="server::id")` — cancel stuck request
- `pmcp_provision(server_name="...")` — install and start a new MCP server

## Cross-Tool Instructions

Universal development principles are maintained in `shared/instructions/core.md` and distributed to all five coding tools (Claude Code, Codex, OpenCode, Gemini CLI, Cursor IDE) by bootstrap.

## Efficiency Skills

The following skills are installed to prevent common anti-patterns:
- `/file-read-cache` — avoid re-reading files you already have in context
- `/safe-edit` — always Read before Edit; check for external modifications
- `/batch-verify` — batch verification after multi-file edits instead of checking each one
- `/diagnose-bash-error` — diagnose bash failures before retrying
- `/validate-before-bash` — preflight checks before running build tools
- `/smart-search` — plan searches and avoid grep/glob thrashing
- `/task-contextualizer` — include file paths and architecture context in subagent prompts
- `/detect-environment` — one-pass tool detection at session start
- `/smart-screenshot` — use snapshot for actions, screenshot only for visual checks
- `/page-load-monitor` — diagnose page load failures instead of blind retries
