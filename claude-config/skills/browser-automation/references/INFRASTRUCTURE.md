# Browser Infrastructure Reference

## System Service

**Service**: `moltbot-headed-browser.service` (systemd user service)
**Display**: Xvfb on `:99` (primary), `:1` is legacy/unused
**Chrome user data**: `~/.config/google-chrome-headed/`

## Port Map

| Port | Protocol | Service | Notes |
|------|----------|---------|-------|
| 9222 | CDP | Headed Chrome | DevTools Protocol for the system Chrome instance |
| 5900 | VNC | x11vnc | Raw VNC access to display :99 |
| 6080 | HTTP | NoVNC | Web-based VNC viewer |

## Chrome Launch Flags

Key flags used by the headed Chrome service:
- `--remote-debugging-port=9222` — enable CDP
- `--user-data-dir=~/.config/google-chrome-headed/` — separate profile from any other Chrome
- `--display=:99` — render to Xvfb virtual display
- `--no-first-run --no-default-browser-check` — skip setup dialogs
- `--disable-gpu` — no GPU in virtual display

## Environment Variables

| Variable | Value | Purpose |
|----------|-------|---------|
| `DISPLAY` | `:99` | Virtual display for headed Chrome |
| `OPENCLAW_BROWSER_CDP_PORT` | `9222` | CDP port for application use |

## VNC Access

View the headed Chrome display:
- **NoVNC** (browser): `http://127.0.0.1:6080`
- **VNC client**: `vnc://127.0.0.1:5900`

## Troubleshooting

Check if headed Chrome is running:
```bash
pgrep -af "chrome.*remote-debugging-port=9222"
```

Check CDP is responsive:
```bash
curl -s http://127.0.0.1:9222/json/version | python3 -m json.tool
```

Check for competing claude-in-chrome sessions:
```bash
pgrep -af "claude-in-chrome-mcp"
```

Restart the headed browser service:
```bash
systemctl --user restart moltbot-headed-browser.service
```
