---
name: browser-automation
description: Guide for browser automation on this machine. Covers when to use Playwright plugin vs claude-in-chrome vs CDP, port/service architecture (Xvfb :99, CDP 9222, VNC 5900/6080), authenticated sessions via storageState, and common pitfalls. Use when performing any browser interaction, taking screenshots, testing web UIs, or debugging extension behavior.
---

# Browser Automation

## Decision Tree

```
Need browser automation?
├─ Extension context needed? (chrome.storage, service workers, extension popups)
│   ├─ Quick/interactive → claude-in-chrome (EZBidPro only, single-session)
│   └─ Scripted/CDP-level → Playwright CDP to :9222 + manual target attachment
│
├─ Need to see the real headed Chrome state? (inspect what user sees on :99)
│   └─ Yes → Playwright CDP connection to 127.0.0.1:9222
│
└─ Everything else (default)
    └─ Playwright plugin (mcp__plugin_playwright_playwright__*)
```

## Playwright Plugin (Default)

Tools: `mcp__plugin_playwright_playwright__browser_*`

Launches its own isolated Chromium — no contention with other sessions, no port conflicts. Use for:
- Screenshots and visual verification
- Form filling, clicking, navigation
- Testing local web apps
- Any browser task that doesn't need the real Chrome instance

Key tools:
- `browser_navigate` — go to URL
- `browser_snapshot` — accessibility tree (better than screenshot for actions)
- `browser_take_screenshot` — visual capture
- `browser_click` / `browser_type` / `browser_fill_form` — interaction
- `browser_evaluate` — run JS on page
- `browser_console_messages` — read console output

### Authenticated Sessions

Save login state:
```javascript
// After logging in, save state
await page.context().storageState({ path: '/tmp/auth-state.json' });
```

Restore in new session:
```javascript
const context = await browser.newContext({ storageState: '/tmp/auth-state.json' });
```

## Playwright CDP Connection

Connect to the real headed Chrome running on display :99:

```python
from playwright.sync_api import sync_playwright
with sync_playwright() as p:
    browser = p.chromium.connect_over_cdp('http://127.0.0.1:9222')
    page = browser.contexts[0].pages[0]  # existing tab
    page.screenshot(path='/tmp/current-state.png')
```

Use when you need to inspect or interact with the actual browser the user sees via VNC. This is read/write access to the real Chrome instance.

## claude-in-chrome

Tools: `mcp__claude-in-chrome__*`

**Restricted to EZBidPro project tree** — disabled globally via `"claude-in-chrome": false` in `enabledPlugins` (`~/.claude/settings.json`). Enabled only in EZBidPro via project-level `enabledPlugins`. The underlying transport is a single WebSocket; only one session can hold it at a time.

Use only when you need access to Chrome extension internals:
- Extension popup/sidebar DOM
- `chrome.storage` API
- Service worker contexts
- Extension-injected content scripts

If tools hang with no response, another session holds the WebSocket — stop and surface to the user.

## Port Deconfliction

- **CDP 9222** — headed Chrome on display :99 (system service)
- **VNC 5900** — raw VNC to display :99
- **NoVNC 6080** — web VNC viewer at `http://127.0.0.1:6080`
- **Playwright** — launches on random ports, fully isolated

Never configure Playwright to use port 9222 unless intentionally connecting to the headed Chrome via CDP.

For full infrastructure details, see [references/INFRASTRUCTURE.md](references/INFRASTRUCTURE.md).

## CDP for Extension Work

CDP can access extension targets on the headed Chrome at `:9222` (persistent profile, extensions loaded).

Procedure:
1. Enumerate targets via `Target.getTargets`.
2. Filter for `type: "service_worker"` or `"background_page"` with `url` starting with `chrome-extension://`.
3. Create a `CDPSession` to the target; enable `Runtime`, `Log`, `Network`, `Storage`.
4. Open extension popups at `chrome-extension://<id>/popup.html` directly in a tab and drive with Playwright selectors.

Rules:
- For MV3 service workers, subscribe to `Target.targetCreated` / `Target.targetDestroyed` and reattach — they unload frequently.
- Access `chrome.storage` via `Runtime.evaluate` on the attached target.
- For content scripts, pass the correct `executionContextId` to `Runtime.evaluate` (isolated worlds).

Use claude-in-chrome instead when you need zero-setup extension access and no other session holds its WebSocket.
