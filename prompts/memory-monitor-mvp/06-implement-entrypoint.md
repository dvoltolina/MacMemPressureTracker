# 06-implement-entrypoint.md

## Task

Implement `scripts/check_memory_pressure.sh` — the launchd-invoked entrypoint that wires the four library modules into one sample → debounce → notify → log loop.

## Context

This is the first user-runnable script in the repo. Every other piece exists to support this one. After this lands, the only remaining work is install/uninstall ergonomics (task 07).

## Required Reading

- `CLAUDE.md`
- `AGENTS.md`
- `ARCHITECTURE.md` (the high-level diagram + "Failure modes" table)
- `CONSISTENCY.md` (the "Error handling" boilerplate)
- `prompts/memory-monitor-mvp/BREAKDOWN.md`
- `config/defaults.sh`
- `lib/log.sh`, `lib/pressure.sh`, `lib/state.sh`, `lib/notify.sh` (read-only)

## Scope Boundaries

May modify:
- `scripts/check_memory_pressure.sh` (new file)
- `tests/check_memory_pressure_test.bats` (new file)
- `CHANGELOG.md`

Off-limits:
- All `lib/` files (treat as read-only API).
- All `launchd/` content.
- Top-level docs except `CHANGELOG.md`.

## Dependencies

All of `02`, `03`, `04`, `05`.

## Implementation Notes

- This file IS executable. Use the `set -Eeuo pipefail` + `trap ERR` boilerplate from `CONSISTENCY.md`.
- Resolve `REPO_ROOT` via `cd "$(dirname "$0")/.." && pwd` and quote everywhere.
- Source order:
  1. `config/defaults.sh`
  2. `~/.config/memory-pressure-monitor/config.sh` (if exists)
  3. `lib/log.sh`, `lib/state.sh`, `lib/notify.sh`, `lib/pressure.sh`
- Main flow:
  1. `pressure::sample` → JSON line.
  2. Always `log::info sample_taken zone=<...> free_pct=<...> ...`.
  3. If `pressure::is_red`:
     - If `state::should_alert red_pressure`: `notify::send "Memory pressure: red" "Free <X>%, compressed <Y>%."` then `state::record_alert red_pressure` and `log::info alert_fired kind=red_pressure`.
     - Else log `log::info alert_suppressed kind=red_pressure reason=cooldown`.
  4. If `pressure::swap_in_use`:
     - Same pattern with `swap_in_use` kind. Body: `Swap in use: <N> MiB.`.
  5. Exit 0.
- Errors anywhere should log via `log::error` and exit non-zero so launchd records the failure but the next tick re-tries.
- The script must run cleanly when invoked directly (not via launchd) for manual testing.
- The integration test (`tests/check_memory_pressure_test.bats`) installs a temporary `PATH` shim so `memory_pressure`, `vm_stat`, and `sysctl` are stubs that print fixture content. The notify backend is set to `stderr` for assertion convenience.

## Acceptance Criteria

- [ ] `make fmt-check` passes
- [ ] `make lint` passes
- [ ] `bats tests/check_memory_pressure_test.bats` covers:
  - normal load: no notification fired, one `sample_taken` log entry
  - red pressure, no prior alert: one notification fired, one `alert_fired` log entry
  - red pressure within cooldown: no notification, one `alert_suppressed` log entry
  - swap in use independent of red pressure: notification fired, correct `kind`
  - simulated parser failure: script exits non-zero, `error` event logged
- [ ] `make test` passes overall
- [ ] `scripts/check_memory_pressure.sh` is executable (`0755`)
- [ ] Manual run on the user's machine produces a sample log entry within seconds

## Documentation Requirement

- Add a dated `CHANGELOG.md` entry: `feat(check): wire entrypoint to pressure/state/notify`.
- Update `REPO_STATUS.md` "In-progress workstreams" to reflect that the libs and entrypoint are done; only install/uninstall remains.

## Commit Requirement

Commit independently with message `feat(check): wire entrypoint to pressure/state/notify`.
