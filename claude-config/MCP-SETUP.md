# MCP Server Setup

This repository is configured with MCP (Model Context Protocol) servers via the PMCP gateway.

## Configuration Files

- `.mcp.json` - Main MCP configuration (references PMCP gateway)
- `.pmcp.json` - PMCP server configuration (filesystem, playwright-cdp)
- `.mcp.json.example` - Template for reference

## Installation

The `bootstrap.sh` script automatically:
1. Expands `$HOME` in `.pmcp.json` to your actual home directory
2. Copies the expanded config to `~/.pmcp.json`
3. Symlinks other Claude Code configuration files

After running `bootstrap.sh`, the MCP gateway will be configured to use `~/.pmcp.json`.

## Available Servers

PMCP provides these servers automatically:

### playwright (default auto-start)
- **Purpose**: Browser automation - navigation, clicks, screenshots, DOM inspection
- **Package**: `@playwright/mcp@latest`
- **Usage**: Automatically launches its own browser instance

### context7 (default auto-start)
- **Purpose**: Library documentation lookup - up-to-date docs for any package
- **Package**: `@upstash/context7-mcp`
- **Usage**: Query documentation for any programming library

### filesystem (custom)
- **Purpose**: Access files in the dotfiles repository
- **Path**: `~/code/dotfiles` (expanded by bootstrap)
- **Usage**: Tools for reading/writing files in your dotfiles

## Adding API Keys

If you need to add API keys for PMCP servers (e.g., GROQ_API_KEY), you have two options:

### Option 1: Add to `.mcp.json` (git-ignored)
```json
{
  "mcpServers": {
    "gateway": {
      "command": "uvx",
      "args": ["pmcp", "-c", "~/.pmcp.json"],
      "env": {
        "GROQ_API_KEY": "your_api_key_here"
      }
    }
  }
}
```

### Option 2: Add to `~/.pmcp.json` (local only)
Add environment variables directly to server configs in `~/.pmcp.json`.

**Note**: `.mcp.json` is git-ignored to protect API keys. See `.mcp.json.example` for template.

## Verifying Setup

Test that the PMCP gateway can start:
```bash
uvx pmcp -c ~/.pmcp.json
```

This should start the gateway and show available MCP servers.

## Plugin vs Gateway

This setup uses the **PMCP gateway** to provide MCP servers instead of individual Claude Code plugins. The Context7 plugin is disabled in `settings.json` to avoid duplication - Context7 is provided through the gateway instead.

Benefits:
- Single unified gateway for all MCP tools
- Cleaner context window (no plugin MCP tool clutter)
- Easier to manage server configurations in one place

## Troubleshooting

### "No such file or directory: ~/.pmcp.json"
Run `./bootstrap.sh` to install the PMCP configuration.

### "Cannot find module @modelcontextprotocol/server-filesystem"
The servers are installed via `npx -y` which auto-installs packages. Ensure you have `npm` installed.

### Paths not resolving correctly
Check that `~/.pmcp.json` has your actual home directory path (not `$HOME` literal). The bootstrap script should have expanded it.
