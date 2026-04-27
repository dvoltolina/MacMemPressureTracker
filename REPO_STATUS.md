# REPO_STATUS.md

> Living status doc. Update this file whenever a meaningful change lands.

---

## Current branch

`main`

## Last meaningful commit

`feat(check+launchd): entrypoint, plist template, install/uninstall` (the v1 shipping commit).

---

## Implemented features

- **memory-monitor-mvp (v1) — shipped 2026-04-27.**
  - launchd user agent samples every `MPM_INTERVAL_SECONDS` (default 30).
  - Notifies via `osascript` when pressure zone is "red" or swap usage exceeds threshold.
  - Cooldowns (`MPM_RED_COOLDOWN_SECONDS=600`, `MPM_SWAP_COOLDOWN_SECONDS=900`) prevent repeat-spam.
  - JSONL log at `~/Library/Logs/memory-pressure-monitor.log`.
  - State file at `state/last_alert.json` (gitignored).
  - Idempotent `install.sh --dry-run/--force` and `uninstall.sh --purge`.
  - Validated end-to-end on macOS 26.1 (build 25B78). Fired and suppressed real swap alerts during installation.

---

## In-progress workstreams

_None._

---

## Known limitations

- **Tested only on macOS 26.1.** The parser relies on the format of `sysctl kern.memorystatus_vm_pressure_level`, `kern.memorystatus_level`, `vm_stat`, and `sysctl vm.swapusage`. Earlier versions are believed to use the same OIDs and formats but are not certified. Add fixtures from any new version under `tests/fixtures/`.
- **No log rotation.** The application log grows monotonically. Defer to v2.
- **No "recovered" notifications.** When pressure returns to normal, no notification is sent. Out of scope for v1.
- **Notification permission must be granted manually.** macOS does not expose a programmatic grant path without app entitlements.
- **No remote git origin yet.** All commits are local-only.
- **CI is dormant.** GitHub Actions workflow is committed but no remote is configured.
- **Dev tools (`bats`, `shellcheck`, `shfmt`) are not installed locally.** All verification was done via manual `bash -n` syntax checks plus end-to-end runs against real fixtures and a real launchd-driven install. The committed bats files have not been executed by the actual `bats` runner.

---

## Open follow-ups

1. ~~Add a git remote (`origin`).~~ Still outstanding — recommended next user-facing action.
2. ~~Capture macOS fixtures.~~ ✅ Done for macOS 26.1.
3. ~~Execute the `memory-monitor-mvp` prompt pack.~~ ✅ Done end-to-end.
4. Audit cadence — kicked off in this same session (next).
5. Decide on log rotation strategy (deferred to v2).
6. Consider a `--reset-cooldown` flag for testing.
7. Add a CI gate that actually runs `bats` once a remote exists.
8. Run `make dev-deps` and execute the committed bats files; resolve any discrepancies between manual validation and real `bats`/`shellcheck` output.

---

## Open questions

- **Notification copy.** Current strings are functional ("Memory pressure: red", "Swap in use"). User feedback may shape final wording.
- **Threshold tuning.** The 64 MiB swap threshold is conservative; adjust if it is too noisy.

---

## Bootstrap assumptions

| # | Assumption | Status post-v1 |
|---|------------|----------------|
| 1 | macOS-only, no Linux/Windows support | ✅ Confirmed and shipped that way |
| 2 | Bash + `launchd` rather than Swift / Python | ✅ Worked; no friction |
| 3 | `osascript` notifications, not `terminal-notifier` | ✅ `osascript` used; `terminal-notifier` available as opt-in |
| 4 | `launchd` user agent (`gui/$UID`), not system daemon | ✅ Correct scope |
| 5 | No remote git origin at bootstrap time | ⚠ Still no remote |
| 6 | ISO 8601 + local offset for timestamps | ✅ Used; verified to be `America/Chicago` (CDT, `-05:00`) |
| 7 | JSONL log format | ✅ Used; validated via `python3 json.loads` |
| 8 | Bundle identifier `com.dominic.memory-pressure-monitor` | ✅ Used |

---

## Audit cadence

The first audit cycle is being run in the same session that shipped v1. Findings and resolution will land in subsequent commits.
