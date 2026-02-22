# Objective

Stabilize and harden the OpenCode runtime environment on a multi-repo Ubuntu cloud dev server where multiple OpenCode instances (TUI + SDK agents) run concurrently.

The current symptoms include blank screens, contention after ~4 instances, and possible shared state conflicts.

The system must support:
- One OpenCode backend per repo
- Concurrent repos
- SDK agents connecting to backends
- TUI attaching to backends
- Cross-repo referencing (read)
- Coordinated cross-repo writes

This is a brownfield system. Do not rewrite. Refactor incrementally.

---

# Phase 1 — Audit

1. Detect whether multiple OpenCode instances share:
   - XDG_DATA_HOME
   - XDG_CONFIG_HOME
   - ~/.local/share/opencode
   - SQLite DB files
   - Cache directories

2. Detect port allocation strategy.
   - Are ports fixed?
   - Are collisions possible?
   - Are SDK agents spawning independent runtimes?

3. Detect if SDK agents instantiate OpenCode runtime directly rather than attaching to existing backend.

4. Confirm whether branch-level session isolation exists at backend level.

5. Detect file descriptor and inotify limits.

---

# Phase 2 — Required Refactor

## A. Per-Repo Runtime Isolation

Implement per-repo state isolation:

For each repo_id:

~/.opencode/repos/<repo_id>/
    data/
    config/
    cache/
    port
    lock

Backends must be launched with:

XDG_DATA_HOME=<repo>/data
XDG_CONFIG_HOME=<repo>/config
XDG_CACHE_HOME=<repo>/cache

No shared state directories allowed.

---

## B. Runtime Manager

Implement a lightweight "Repo Runtime Manager" (RRM) that:

- Computes stable repo_id
- Detects if backend running
- Allocates dynamic free port via OS bind(0)
- Persists endpoint to registry file
- Starts backend process
- Performs health check
- Tracks PID
- Cleans stale registry entries

Expose function:

ensureRunning(repoRoot) -> endpoint

All SDK agents and TUIs must call ensureRunning() instead of launching opencode directly.

---

## C. SDK Agent Policy

Enforce:

- SDK agents must not spawn OpenCode runtime using defaults
- SDK agents must connect to repo backend endpoint from registry
- No direct OpenCode initialization inside SDK without isolation

---

## D. Cross-Repo Mutation Router

If a tool attempts to write outside current repo root:

1. Detect target repo
2. Forward write to correct repo backend
3. Acquire target repo lock
4. Apply mutation via that backend

Do NOT allow direct cross-repo file writes bypassing backend.

---

## E. Concurrency Model

Enforce per repo:

- 1 active write session per branch
- Concurrent reads allowed
- Serialize write tool calls
- Use file-based lock or advisory lock

---

## F. Resource Hardening

- Increase ulimit -n to >= 65535
- Increase fs.inotify.max_user_watches to >= 1048576
- Bind backends to 127.0.0.1 only
- Log memory usage per backend

---

# Deliverables

- Refactored runtime manager module
- Isolation verified
- No shared SQLite files across repos
- Stable multi-repo operation > 10 simultaneous repos
- No blank screen condition reproducible
- Documented lifecycle behavior

Do not remove cross-repo referencing.
Do not enforce artificial filesystem jail.
Preserve local-first model.

End.
