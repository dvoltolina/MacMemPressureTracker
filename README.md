# memory-pressure-monitor

A personal macOS notification system that alerts when memory pressure enters the critical ("red") zone or the system begins using swap.

> **Status:** v1 shipped — installed and validated on macOS 26.1.

---

## Why

macOS's Activity Monitor surfaces memory pressure visually but does not push notifications when pressure becomes critical. This tool runs as a `launchd` user agent, samples the relevant sysctls and `vm_stat` on an interval, and posts a native notification when:

1. `kern.memorystatus_vm_pressure_level` reports **critical** (`4`), or
2. `vm.swapusage` shows used > `MPM_SWAP_THRESHOLD_MIB` MiB (default 64).

It is intentionally minimal: no GUI, no daemon manager, no cloud sync. Just a script, a plist, and an installer.

---

## Requirements

- macOS 12 or newer (developed and tested on 26.1).
- `bash` 3.2+ (the system shell on every Mac).
- No third-party runtime dependencies.

Optional for development:
- [`bats-core`](https://github.com/bats-core/bats-core) for the test suite.
- [`shellcheck`](https://www.shellcheck.net/) for linting.
- [`shfmt`](https://github.com/mvdan/sh) for formatting.

Install dev deps via `make dev-deps` (uses Homebrew).

---

## Quick start

```sh
# Install the launchd user agent (renders plist + launchctl bootstrap)
./scripts/install.sh

# See what plist would be installed without actually installing
./scripts/install.sh --dry-run

# Reload after editing config or the entrypoint
./scripts/install.sh --force

# Watch the structured log
tail -f ~/Library/Logs/memory-pressure-monitor.log

# Stop and remove the agent (preserves state and logs)
./scripts/uninstall.sh

# Stop, remove agent, AND wipe state + logs
./scripts/uninstall.sh --purge
```

---

## First-run notification permission

The first time the agent fires a notification, macOS may show a system prompt asking whether to allow notifications from `Script Editor` (or whichever process is invoking `osascript`). **Approve it once** to receive future alerts. There is no programmatic way to grant this permission — that's a macOS security feature.

If you missed the prompt, you can grant it manually:
- System Settings → Notifications → Script Editor → Allow Notifications.

---

## Configuration

Defaults live in `config/defaults.sh`. To override, create `~/.config/memory-pressure-monitor/config.sh` with any of:

```sh
MPM_INTERVAL_SECONDS=30           # how often launchd ticks
MPM_RED_COOLDOWN_SECONDS=600      # 10 min between red-zone alerts
MPM_SWAP_COOLDOWN_SECONDS=900     # 15 min between swap alerts
MPM_SWAP_THRESHOLD_MIB=64         # treat swap as "in use" above this
MPM_NOTIFICATION_BACKEND=osascript  # or terminal-notifier
MPM_NOTIFICATION_SOUND=Submarine  # any system sound; empty = silent
MPM_LOG_PATH="$HOME/Library/Logs/memory-pressure-monitor.log"
```

Re-run `./scripts/install.sh --force` after editing config so the new values get picked up.

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
├── scripts/             # Bash entrypoints (check, install, uninstall)
├── lib/                 # Sourced helpers (log, pressure, state, notify)
├── launchd/             # launchd plist template
├── tests/               # bats-core test suite + fixtures
├── config/              # Default config
└── prompts/             # Prompt packs for future agent work
```

---

## Verifying it works

```sh
# Confirm the agent is loaded
launchctl print "gui/$(id -u)/com.dominic.memory-pressure-monitor" | head -10

# Trigger a sample manually (useful when iterating)
./scripts/check_memory_pressure.sh

# See the most recent samples
tail ~/Library/Logs/memory-pressure-monitor.log
```

---

## For agents

If you are an automated agent, **start at `CLAUDE.md`**. Do not begin work without reading the required documentation listed there.

---

## License

Personal project — no license declared. Not intended for redistribution.
