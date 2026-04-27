# memory-pressure-monitor

A personal macOS notification system that alerts when memory pressure enters the "red" state or the system begins using swap.

> **Status:** scaffolded — feature implementation pending. See `REPO_STATUS.md` and `prompts/memory-monitor-mvp/INDEX.md` for the next steps.

---

## Why

macOS's Activity Monitor surfaces memory pressure visually but does not push notifications when pressure becomes critical. This tool runs as a `launchd` user agent, samples memory pressure on an interval, and posts a native notification when:

1. Memory pressure transitions into the **red** zone, or
2. Compressed/swap usage crosses a configurable threshold.

It is intentionally minimal: no GUI, no daemon manager, no cloud sync. Just a script, a plist, and an installer.

---

## Requirements

- macOS 12 or newer (uses `memory_pressure`, `vm_stat`, `sysctl`, `osascript`).
- `bash` 3.2+ (the system shell on every Mac).
- No third-party dependencies.

Optional for development:
- [`bats-core`](https://github.com/bats-core/bats-core) for the test suite (`brew install bats-core`).
- [`shellcheck`](https://www.shellcheck.net/) for linting (`brew install shellcheck`).
- [`shfmt`](https://github.com/mvdan/sh) for formatting (`brew install shfmt`).

---

## Quick start (once implemented)

```sh
# Install the user agent
./scripts/install.sh

# Tail the log
tail -f ~/Library/Logs/memory-pressure-monitor.log

# Uninstall
./scripts/uninstall.sh
```

---

## Repo layout

```
.
├── CLAUDE.md            # Agent-facing top-level guidance
├── AGENTS.md            # Full agent operating procedure
├── ARCHITECTURE.md      # System architecture
├── CONSISTENCY.md       # Cross-cutting conventions
├── REPO_STATUS.md       # Living status doc
├── CHANGELOG.md         # Dated changelog of all work
├── README.md            # This file (human-facing)
├── scripts/             # Bash entrypoints
├── lib/                 # Shared shell helpers
├── launchd/             # launchd plist templates
├── tests/               # bats-core test suite
├── config/              # Default config (thresholds, intervals)
└── prompts/             # Prompt packs for future agent work
```

---

## For agents

If you are an automated agent, **start at `CLAUDE.md`**. Do not begin work without reading the required documentation listed there.

---

## License

Personal project — no license declared. Not intended for redistribution.
