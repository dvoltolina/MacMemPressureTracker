# ARCHITECTURE.md

## High-level diagram

```
              ┌────────────────────────────────────────────┐
              │              macOS user session             │
              │                                            │
   launchd ──►│  scripts/check_memory_pressure.sh          │
   (every N s)│      │                                     │
              │      ├─► lib/pressure.sh  ──► memory_pressure
              │      │                       vm_stat
              │      │                       sysctl vm.swapusage
              │      │
              │      ├─► lib/state.sh ◄──► state/last_alert.json
              │      │                     (debounce + history)
              │      │
              │      ├─► lib/log.sh   ──► ~/Library/Logs/
              │      │                    memory-pressure-monitor.log
              │      │
              │      └─► lib/notify.sh ──► osascript display notification
              │                            (or terminal-notifier opt-in)
              └────────────────────────────────────────────┘
```

Single-process, no daemon, no IPC, no network. Each `launchd` tick is one short-lived bash invocation.

---

## Components

### `scripts/check_memory_pressure.sh`
The user-facing entrypoint invoked by `launchd`. Reads config, calls `lib/pressure.sh` to sample the system, calls `lib/state.sh` to determine whether to alert (debounce), calls `lib/notify.sh` to fire the notification, and calls `lib/log.sh` to record the sample. Exits non-zero only on internal error — a benign "no alert needed" path is exit 0.

### `lib/pressure.sh`
Pure-shell parser for memory metrics. Functions:
- `pressure::sample` — runs `memory_pressure -Q` (or equivalent), returns a normalized record (`zone=normal|warn|red`, `free_pct`, `compressed_pct`).
- `pressure::swap_in_use` — parses `sysctl vm.swapusage`, returns swap-used MiB.
- `pressure::is_red` — pure decision function over a sample record.

The parser must accept fixture files via stdin so it is testable without root or a real device.

### `lib/state.sh`
Manages `state/last_alert.json`. Functions:
- `state::should_alert` — returns 0 if cooldown has elapsed since the last alert of the same kind.
- `state::record_alert` — writes a new alert record.
- `state::reset` — clears state (used by `scripts/uninstall.sh`).

State file is local-only, world-readable, owner-writable (`0644`). It is not encrypted; nothing in it is sensitive.

### `lib/log.sh`
Append-only structured log. One JSON object per line. Functions:
- `log::info`, `log::warn`, `log::error`
- Rotation is delegated to `launchd`'s `StandardOutPath` / `StandardErrorPath` and a periodic external `logrotate` invocation, **not** implemented in v1.

### `lib/notify.sh`
Notification driver. Default backend is `osascript`. Functions:
- `notify::send` — title, body, optional sound name.
- Falls back to a `printf` to stderr if no notification backend is available (CI mode).

### `launchd/com.dominic.memory-pressure-monitor.plist.tmpl`
Template plist with placeholders `__REPO_PATH__`, `__INTERVAL__`, `__LOG_PATH__`. Rendered by `scripts/install.sh` at install time.

### `scripts/install.sh` and `scripts/uninstall.sh`
Idempotent installer and uninstaller for the user agent. Install copies the rendered plist to `~/Library/LaunchAgents/`, runs `launchctl bootstrap gui/$UID ...`, and verifies the agent is loaded. Uninstall reverses this and optionally removes the state file.

---

## Data model

There is no database. Two on-disk files:

### `state/last_alert.json`
```json
{
  "schema": 1,
  "last_alert": {
    "red_pressure": "2026-04-27T08:45:00-07:00",
    "swap_in_use":  "2026-04-27T08:45:00-07:00"
  }
}
```

- `schema` — integer, bumped on backwards-incompatible changes.
- `last_alert.<kind>` — ISO 8601 timestamp with offset, or `null` if never fired.

### `~/Library/Logs/memory-pressure-monitor.log`
Append-only JSONL. One sample per line:
```json
{"ts":"2026-04-27T08:45:00-07:00","level":"info","zone":"normal","free_pct":42.1,"compressed_pct":3.7,"swap_used_mib":0}
```

No PII. No bundle paths beyond the repo path. Safe to share for debugging.

---

## Auth / permissions

- **No authentication.** Single-user tool.
- **No elevation.** All operations run as the user. `launchd` user agent, not a system daemon.
- **File permissions:** state file `0644`, log file `0644`, plist `0644`, scripts `0755`.
- **Notification permission:** the first run will trigger a macOS prompt asking the user to grant notification permission to whichever process invokes `osascript` (typically `Script Editor` or the Terminal). This is documented in `README.md`.

---

## External integrations

- **None.** No HTTP, no Slack, no email, no telemetry.
- Future work (out of scope for v1): optional Slack webhook, optional Pushover.

---

## Deployment topology

- **Personal device only.** No staging, no production environments.
- **CI** runs on GitHub-hosted `macos-latest` runners and is limited to lint, format, and the subset of tests that work with synthetic fixtures (the `memory_pressure` binary on hosted runners may not produce realistic output).
- **No release artifacts.** Users (the user — singular) clone the repo and run `./scripts/install.sh`.

---

## Failure modes and graceful degradation

| Failure | Behavior |
| --- | --- |
| `memory_pressure` returns unexpected output | Log a warning, skip this tick, do not crash. |
| State file corrupted (invalid JSON) | Treat as "no prior alerts", overwrite on next alert. Log a warning. |
| `osascript` missing or fails | Fall back to stderr `printf`; `launchd` logs capture it. |
| Disk full (cannot write log) | Log error to stderr (captured by `launchd`); proceed. |
| Notification permission revoked | Notification silently fails; logged at warn level. |
| Clock skew / wall clock jumps backward | Debounce may misbehave for one cycle; corrects on next tick. |

---

## Versioning

- The `state/last_alert.json` schema is versioned via the `schema` integer. Migrations live in `lib/state.sh::state::migrate`.
- The plist template carries the bundle identifier `com.dominic.memory-pressure-monitor`. Do not change without a coordinated uninstall step.
