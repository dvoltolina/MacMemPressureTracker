# BREAKDOWN — memory-monitor-mvp

> Risk and architecture breakdown produced before any task prompt is executed. Authored during repo bootstrap. Confirm or update before kicking off the first real implementation.

---

## Workstream goal

Ship the minimum viable end-to-end loop:

1. `launchd` invokes `scripts/check_memory_pressure.sh` every `MPM_INTERVAL_SECONDS`.
2. The script samples `memory_pressure`, `vm_stat`, and `sysctl vm.swapusage`.
3. If pressure is "red" or swap is in active use, the script fires a macOS notification.
4. A debounce window prevents repeat notifications within a cooldown.
5. Every sample is logged as JSONL.

When the workstream is done, the user can install the agent with one command and receive notifications under real load.

---

## 1. Feature areas affected

- Sampling (new): `lib/pressure.sh`
- State (new): `lib/state.sh`, `state/last_alert.json` (gitignored)
- Logging (new): `lib/log.sh`, `~/Library/Logs/memory-pressure-monitor.log`
- Notifications (new): `lib/notify.sh`
- Entrypoint (new): `scripts/check_memory_pressure.sh`
- Installation (new): `scripts/install.sh`, `scripts/uninstall.sh`
- launchd template (new): `launchd/com.dominic.memory-pressure-monitor.plist.tmpl`
- Tests (new): `tests/{pressure,state,log,notify,check_memory_pressure}_test.bats`
- Fixtures (new): `tests/fixtures/{memory_pressure,vm_stat,sysctl_swapusage}_*.txt`

## 2. Files likely to change

| Path | Why |
| --- | --- |
| `lib/pressure.sh` | Parser for `memory_pressure`/`vm_stat`/`sysctl vm.swapusage` |
| `lib/state.sh` | Read/write `state/last_alert.json` with debounce logic |
| `lib/log.sh` | Append-only JSONL logger |
| `lib/notify.sh` | `osascript` notification driver with stderr fallback |
| `scripts/check_memory_pressure.sh` | Main entrypoint |
| `scripts/install.sh` | Render plist, `launchctl bootstrap`, verify |
| `scripts/uninstall.sh` | `launchctl bootout`, remove plist, optional state cleanup |
| `launchd/com.dominic.memory-pressure-monitor.plist.tmpl` | Template plist |
| `tests/*.bats` and `tests/fixtures/*.txt` | Coverage |
| `CHANGELOG.md` | Dated entry per task |
| `REPO_STATUS.md` | Mark feature implemented when done |
| `README.md` | Real install/run/uninstall commands |

## 3. Data model implications

- New file: `state/last_alert.json`. Schema documented in `ARCHITECTURE.md`. Bumping the schema requires a migration in `lib/state.sh::state::migrate`.
- Log lines append to `~/Library/Logs/memory-pressure-monitor.log`. Rotation deferred to v2.

## 4. API / backend / service changes

None. No network, no external services.

## 5. Security / permissions / policy changes

- launchd user agent label `com.dominic.memory-pressure-monitor` (in `gui/$UID` domain). Not a system daemon.
- Plist permissions: `0644`. Scripts: `0755`. State and log: `0644`.
- No secrets handled.
- macOS will prompt the user once for notification permission. Document in README.
- No `sudo` required at any point.

## 6. Storage or file-handling changes

- `state/` directory created lazily by `lib/state.sh::state::record_alert`.
- Log file created lazily by `lib/log.sh::log::info` on first write.
- `scripts/uninstall.sh --purge` removes both. Without `--purge`, state is kept so reinstalls preserve cooldowns.

## 7. Backward compatibility concerns

None — this is the first release. No prior versions, no migrations needed. The state file `schema` field is set to `1` from day one to leave migration headroom.

## 8. Migration concerns

None at v1. State migration code is a stub that only handles `schema=1`.

## 9. User-facing edge cases

- **First run, no notification permission yet.** Notification silently fails until the user grants it. Log a warning.
- **`memory_pressure` returns unexpected output.** Log warning, skip this tick. Do not crash the launchd-managed process.
- **Clock skew or system sleep.** Cooldown is computed from a wall-clock timestamp; if the wall clock jumps, debounce may fire one extra notification. Acceptable for v1.
- **Disk full.** Logging fails; the launchd `StandardErrorPath` captures the error. Sampling proceeds.
- **State file corrupted (manual edit, partial write).** Treat as "no prior alerts"; overwrite on next alert. Log warning.
- **Repo path contains spaces.** Already true for this repo. The installer must quote everything and substitute the absolute path into the plist's `WorkingDirectory` and `ProgramArguments`.
- **User runs install.sh twice.** Idempotent: skip the bootstrap if already loaded; replace the plist if content differs.
- **Notification posted while another notification is on screen.** macOS coalesces; treat any post as success.

## 10. Testing strategy

- **Unit-level (bats-core, no real device side effects):**
  - `lib/pressure.sh` parser — feed each `tests/fixtures/*.txt` and assert the normalized record.
  - `lib/state.sh` — set `TEST_NOW` env var, exercise cooldown boundary cases.
  - `lib/log.sh` — assert JSONL output is one valid object per call.
  - `lib/notify.sh` — assert that with backend `stderr` (test-only), the right message lands on stderr.
- **Integration-level (still no real device):**
  - `tests/check_memory_pressure_test.bats` invokes the entrypoint with a stubbed `PATH` providing fake `memory_pressure`/`vm_stat`/`sysctl` binaries that print fixture content. Asserts no notification fires under nominal load and one fires under red load.
- **Manual QA on the user's actual MacBook:**
  - Install. Confirm `launchctl print gui/$UID/com.dominic.memory-pressure-monitor` shows the agent loaded.
  - Trigger memory pressure (e.g. `stress-ng --vm 2 --vm-bytes 80%` or load a few large apps). Confirm a notification appears.
  - Wait inside the cooldown window and confirm a second notification does NOT appear.
  - Uninstall. Confirm `launchctl print` no longer lists the label, plist is gone, and (with `--purge`) state file is gone.

## 11. Manual QA checklist

- [ ] Install completes without error on a clean machine.
- [ ] First sample log entry appears within `MPM_INTERVAL_SECONDS`.
- [ ] Synthetic red-pressure event produces exactly one notification.
- [ ] No second notification within cooldown.
- [ ] Notification copy is concise and points at "memory pressure" or "swap" specifically.
- [ ] Uninstall is idempotent (running twice does not error).
- [ ] Uninstall without `--purge` preserves state.
- [ ] Uninstall with `--purge` removes state and log.
- [ ] Path with spaces in the repo path does not break install.

## 12. Known non-goals for this workstream

- No GUI, menu-bar app, or status icon.
- No history dashboard, plotting, or export.
- No remote alerting (Slack, email, Pushover).
- No log rotation (deferred to v2).
- No multi-user support; single user only.
- No homebrew packaging or release artifacts.
- No automatic granting of notification permission (cannot be done programmatically without entitlements).
- No "recovered" notifications when pressure returns to normal (deferred — would require additional state and is bikesheddable).

---

## Open questions to resolve before tasks 01–06 are executed

1. Confirm the user's macOS major version so fixtures match (`sw_vers -productVersion`).
2. Confirm the launchd label `com.dominic.memory-pressure-monitor` is acceptable.
3. Confirm cooldown defaults (10 min red, 15 min swap) are reasonable for the user's workload.
4. Confirm whether a "recovered" notification is in or out of v1.
