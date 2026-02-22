# Global Claude Instructions

See AGENTS.md for agent-specific instructions.

## Interactive Testing Workflow

**CRITICAL**: Always test UI features interactively in the browser before marking them complete.

Default to **Playwright plugin** tools (`mcp__plugin_playwright_playwright__*`) for all browser automation. These launch an isolated browser with no contention issues.

`claude-in-chrome` tools are only available in EZBidPro sessions (disabled globally) — use only when Chrome extension contexts are needed.

For full details on tool selection, CDP connections, authenticated sessions, and infrastructure: invoke `/browser-automation`.

### Quick Reference

```
browser_navigate(url)          → go to URL
browser_snapshot()             → accessibility tree (preferred for actions)
browser_take_screenshot()      → visual capture
browser_click(ref, element)    → click element from snapshot
browser_type(ref, text)        → type into element
browser_evaluate(function)     → run JS on page
browser_console_messages()     → read console output
```

### Testing Checklist

```
[ ] Load page and take screenshot
[ ] Verify UI elements are visible
[ ] Test interactive controls
[ ] Check browser console for errors
[ ] Verify expected behavior
```

## MCP Gateway (PMCP)

An MCP gateway is available via tools prefixed with `mcp__gateway__`. Before reaching for Bash workarounds or telling the user something isn't possible, check whether the gateway has a tool for it.

**Plugin vs Gateway**: Playwright is available directly as `mcp__plugin_playwright_playwright__*` (preferred for browser automation). The gateway provides additional capabilities like Context7 docs lookup and on-demand server provisioning.

**Discovery workflow**: `gateway_catalog_search` -> `gateway_describe` -> `gateway_invoke`

**Library docs (Context7)**:
1. `gateway_invoke(tool_id="context7::resolve-library-id", arguments={"libraryName": "react"})`
2. `gateway_invoke(tool_id="context7::get-library-docs", arguments={"context7CompatibleLibraryID": "/facebook/react", "topic": "hooks"})`

**Natural language discovery**: `gateway_request_capability(query="I need to search Slack messages")` — matches to installed tools or provisions new servers.

**Operational tools** (for debugging hangs or checking status):
- `gateway_health` — server status and tool counts
- `gateway_list_pending` — in-flight requests with elapsed time
- `gateway_cancel(request_id="server::id")` — cancel stuck request
- `gateway_provision(server_name="...")` — install and start a new MCP server

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
