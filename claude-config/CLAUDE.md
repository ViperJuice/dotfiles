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

**When to use**: Library documentation lookup, headless browser automation (Playwright), or any capability you don't have natively.

**Workflow**: `gateway_catalog_search` → `gateway_describe` → `gateway_invoke`

1. **Search**: `gateway_catalog_search(query="browser screenshot")` — returns compact capability cards
2. **Describe**: `gateway_describe(tool_id="playwright::browser_take_screenshot")` — get full schema
3. **Invoke**: `gateway_invoke(tool_id="playwright::browser_take_screenshot", arguments={...})` — execute

**Don't know the tool name?** Use `gateway_request_capability(query="I need to look up React docs")` — it matches natural language to available tools and can provision new servers on-demand.

**Key tools available now**: Playwright (headless browser, 22 tools), Context7 (library docs lookup). More can be provisioned via `gateway_provision`.
