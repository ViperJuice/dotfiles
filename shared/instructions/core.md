# Core Development Instructions

Universal principles for AI-assisted coding tools.

## Code Quality

- Prefer modifying existing code over creating new files or functions
- Follow existing conventions (style, architecture, naming, patterns)
- Keep changes minimal and focused — only change what was requested
- Don't add features, refactoring, comments, or type annotations beyond the task
- Don't add speculative error handling or validation for scenarios that can't happen

## Safety

- Never run destructive commands (force push, reset --hard, rm -rf) without explicit request
- Never commit secrets, credentials, or API keys
- Don't discard or revert unrelated user changes
- Verify changes build and tests pass before marking work complete
- Validate at system boundaries (user input, external APIs), trust internal code

## Workflow

- Research the codebase first — search for existing functions, utilities, and patterns
- Use search tools to discover relevant code paths before editing
- Read files before editing them
- Reproduce problems or confirm current behavior before fixing
- Run the narrowest verification first (targeted tests), then broader checks

## Efficiency

- Don't re-read files you already have in context
- Diagnose errors before retrying failed commands
- Batch verification for multi-file edits instead of checking each one
- Plan searches before executing — avoid repeated similar searches
- Use the right tool for the job (file tools for files, search tools for search)

## Code Search

- Prefer `rg` (ripgrep) over `grep` for code search — faster, respects `.gitignore`, better regex
- Use `rg` for file contents, `find`/glob tools for file names
- Key flags: `--type ts` (filter by language), `-i` (case-insensitive), `-C 3` (context lines), `-l` (file paths only), `--count` (match counts)
- Ripgrep uses Rust regex, NOT PCRE. Escape these for literal matches: `{ } ( ) [ ] . * + ? ^ $ |`
  - Common mistake: searching for `interface{}` without escaping → use `interface\{\}`
  - Common mistake: searching for `foo.bar()` without escaping → use `foo\.bar\(\)`

## Browser Testing

- Test UI features interactively before marking them complete
- Use accessibility snapshots for element interaction (clicking, typing)
- Use screenshots only for visual verification
- Check browser console for errors after interactions
- Diagnose page load failures instead of blind retries
