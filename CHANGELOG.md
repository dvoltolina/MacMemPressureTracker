# Changelog

All notable changes to this repo are recorded here, grouped by date.

Format conventions:
- One H2 heading per calendar date (`## YYYY-MM-DD`).
- Within each date, group entries by area (`### Bootstrap`, `### Docs`, `### Scaffolding`, `### Feature: <name>`, `### Fixes`).
- Each entry is a bullet beginning with a Conventional Commits prefix matching the related commit (`feat:`, `fix:`, `chore:`, `docs:`, `refactor:`, `test:`).

---

## 2026-05-02

### Audit fixes for kill-from-popup

- `fix(app):` correct the `ps -o comm=` semantics in `ProcessLister` and `NeverKill`. The audit identified that on macOS `comm=` returns the FULL executable path for most processes (e.g. `/sbin/launchd`) and only a bare basename for a few (interactive-shell binaries like `claude`, kernel-side processes). The functional behavior was correct because `lastPathComponent` extraction handles both shapes; this commit aligns the comments with reality and notes that the secondary `names.contains(row.command.lowercased())` check is defense-in-depth, not redundant.
- `fix(app):` harden `buildProcessTable` against duplicate PIDs in the `ps` output. `Dictionary(uniqueKeysWithValues:)` calls `fatalError` on duplicate keys, which would crash the popup mid-alert (silently, since `nohup ... > /dev/null 2>&1 &` discards the panic). Replaced with an explicit last-write-wins loop.
- `fix(app):` change the alert popup auto-dismiss from `NSApp.abortModal()` to `NSApp.terminate(nil)`. `abortModal` only aborts the innermost modal session, so if the timer fired while the user was sitting on a nested Quit confirmation, refusal alert, or kill-error alert, the inner alert aborted and the outer popup was orphaned with no remaining auto-dismiss. `terminate` closes the entire popup process regardless of nesting depth.
- `fix(app):` stop assigning a `Pipe` to `task.standardError` in `ProcessLister`. Setting an unread pipe risks a `waitUntilExit` deadlock if `ps` ever writes more than the pipe buffer (~64 KB) to stderr. stderr now inherits, which is `/dev/null` on the launchd `nohup` path.
- `fix(app):` re-validate the PID/comm mapping after the user confirms Quit, before sending `SIGTERM`. The popup can sit on screen for up to 90 s; if the original PID exits and macOS recycles it, sending `SIGTERM` to the recycled PID could hit a process the user never saw. Now `ProcessLister.commForPid(_:)` runs `/bin/ps -o comm= -p <pid>` after the confirmation; if the PID is gone or the command no longer matches the displayed row, the kill is aborted with an explanatory alert.

---

## 2026-04-30

### Feature: kill-from-popup

- `feat(notify):` plumb `MPM_POPUP_ALLOW_QUIT` (default `0`) through `config/defaults.sh`, the `lib/config.sh` validator, and `lib/notify.sh`. When set to `1`, the popup backend appends `--allow-quit` to the dashboard binary's argv. The binary will use this flag in a follow-up commit to render per-row Quit buttons. Default off; the existing advisory popup behavior is unchanged for users who do not opt in.
- `feat(app):` per-row "Quit" buttons in the alert popup when launched with `--allow-quit`. Tapping Quit shows a `Send SIGTERM to <name>?` confirmation; on confirm, sends `SIGTERM` via `kill(2)` and disables the row's button with a status annotation. A hardcoded never-kill list (`launchd`, `WindowServer`, `Finder`, `Dock`, `SystemUIServer`, `loginwindow`, `mds`, `mds_stores`, `mdworker`, `mdworker_shared`, `securityd`, `coreaudiod`, `hidd`, `syslogd`, `runningboardd`, `powerd`, `configd`, `kernel_task`, `Memory Pressure Monitor`) plus PID < 200 and uid 0 refusals block system-critical processes regardless of the env. `kill()` errors are surfaced as user-visible alerts: `ESRCH` → "already gone", `EPERM` → "permission denied — try Activity Monitor". `AppArguments.parse` learned a boolean-flag mode for `--allow-quit` (does not consume the next argv as a value). `ProcessLister` now captures `uid` from `ps -o pid=,uid=,rss=,comm=` so the uid-0 check is enforceable. SIGKILL escalation is intentionally not supported.
- `docs:` README config table gains the `MPM_POPUP_ALLOW_QUIT` row plus a paragraph in the Notification Backend section. ARCHITECTURE alert-mode description updated (no longer "advisory only") and Auth/permissions section gains a Signal-sending bullet. REPO_STATUS follow-up #10 marked done.

---

## 2026-04-29

### Feature: dashboard

- `feat(app):` live pressure chart in the dashboard window. Reads the JSONL log directly (last 256 KB tail), filters `sample_taken` events, and draws the last 240 samples as a blue line/area with per-sample dots colored by zone (green=normal, orange=warn, red=critical). HH:MM tick labels at the X-edges, 0/25/50/75/100% gridlines on the Y-axis, and a top-right legend showing the most recent free %, zone, and swap MiB. Auto-refreshes every 15 s while the window is open. Window default size bumped to 680×600 with min 560×520 to fit the chart.

### Feature: active-alerts

- `feat(state):` schema 2 — replace the boolean `swap_active` field with a `swap_alerted_mib` integer high-water mark, and add a `warn_pressure` last-alert slot. Schema 1 is read transparently and rewritten as schema 2 on the next alert update. New API: `state::swap_alerted_mib`, `state::set_swap_alerted_mib`, `state::record_alert <kind> [<swap_used_mib>]`.
- `feat(check):` warn-zone alerts and swap-growth re-fire. The decision rule now fires `warn_pressure` (separate cooldown) when not already firing red, and re-fires `swap_in_use` when current swap exceeds `swap_alerted_mib + MPM_SWAP_GROWTH_MIB`. Closes the missed-alert path where a machine that lived in `warn` zone with multi-GiB swap got no notifications after the first boot-time observation.
- `feat(config):` new keys `MPM_WARN_ALERTS_ENABLED` (default 1), `MPM_WARN_COOLDOWN_SECONDS` (default 1800), `MPM_SWAP_GROWTH_MIB` (default 1024). Validated in `lib/config.sh`.
- `feat(notify):` new `popup` backend that runs the dashboard binary in `--alert` mode detached. Falls back to `osascript` if the app bundle is missing, logging `notify_fallback reason=app_missing`. Default `MPM_NOTIFICATION_BACKEND` changes from `osascript` to `popup`. `notify::send` signature gains forwarded `kind` and per-alert context args (`--zone`, `--free-pct`, `--swap-mib`).
- `feat(app):` `--alert` mode in the dashboard binary. Argv contract: `--alert <kind> --title <text> --body <text> [--zone <z>] [--free-pct <n>] [--swap-mib <n>]`. Shows a centered, floating, frontmost `NSAlert` with a top-8-by-RSS process table and two buttons: "Open Activity Monitor" and "Dismiss". Auto-dismisses after 90 s. Advisory only — does not kill processes.
- `docs:` align README, ARCHITECTURE, and REPO_STATUS with active-alerts. Add new config table to README.

### Audit Fixes

- `fix(state):` flatten newlines in `_state::extract_int` so a pretty-printed schema-2 state file (one field per line, hand-edited or migrated by future tooling) is read correctly. Without the flatten, `state::swap_alerted_mib` returned 0 on multi-line files and the next tick fired a spurious "first observed" swap alert.
- `fix(state):` defensively clamp `swap_alerted_mib` to 12 digits on read and write. A corrupt or interrupted-write value larger than that would either truncate or trip `set -Eeuo pipefail` in the consumer's arithmetic and silently abort future ticks.
- `fix(notify):` skip launching a second popup when one from a prior tick is still visible (`pgrep` against the alert-mode argv pattern). The cooldown still starts so the suppression is bounded; the visible popup already conveys the situation.
- `fix(notify):` remove the undocumented `MPM_POPUP_APP_BINARY` env override. It was an unvalidated trust input that would let any code that could set it route every alert through an attacker-chosen binary. The repo-relative resolution is the only path now.
- `fix(app):` argv parser rejects values that begin with `--` so a caller dropping a flag's value (e.g. `--title --body hi`) cannot silently misalign the parse and disable alert mode.
- `fix(app):` log and surface a fallback alert when Activity Monitor cannot be located at the standard `/System/Applications/Utilities` or `/Applications/Utilities` path, instead of silently no-op.
- `fix(app):` strengthen the popup advisory copy from "Use Activity Monitor to inspect or quit a process." to "To free memory: open Activity Monitor and Quit the largest process you don't need."
- `fix(check):` defensively default `prev_alerted` to 0 after capturing from `state::swap_alerted_mib` so a future refactor that lets the helper return empty cannot abort the tick under `set -u`.
- `docs:` record audit findings, fixes, and outstanding follow-ups (stale bats suite needs rewriting to schema-2 contract; popup silent-failure detection deferred).

### Feature: dashboard heartbeat

- `feat(app):` dashboard now shows a "Last sample Ns ago" indicator that updates every second, parsed from the most recent log entry's `ts` field. Idle copy is "Waiting for first sample..."; the label turns red after 150 s without a fresh sample so a stalled `launchd` agent is visible without watching the chart. Addresses REPO_STATUS follow-up #12.

### Tests

- `test(state):` rewrite `tests/state_test.bats` to the schema-2 contract. New coverage: schema-1 → schema-2 read migration (with and without `swap_active`), schema-1 → schema-2 file rewrite on next `record_alert`, per-kind cooldown routing (`warn_pressure` distinct from `red_pressure` distinct from `swap_in_use`), `swap_alerted_mib` preservation across non-swap kinds, B1 audit regression (pretty-printed integer parse via newline flatten), S-2 audit regression (>12-digit width clamp on read), `set_swap_alerted_mib` rejecting non-integer input. 27 tests, all passing under `bats tests/state_test.bats`. Partial completion of REPO_STATUS follow-up #8; `check_memory_pressure_test.bats` and `notify_test.bats` still pending.

### Fixes

- `fix(app):` add explicit `static func main()` so the dashboard's AppKit run loop actually starts. Without it, `@main` on a bare `NSApplicationDelegate` synthesizes a no-op entry point, `applicationDidFinishLaunching` never fires, and the window never appears (the user reported "no available windows").

---

## 2026-04-27

### Bootstrap

- `chore:` initial scaffold — empty repo with `.gitignore` and placeholder `README.md` (commit `579c118`).

### Docs

- `docs:` add `CLAUDE.md` top-level agent guidance (commit `19f1802`).
- `docs:` add `AGENTS.md` 10-step operating procedure (commit `bbe9c6d`).
- `docs:` add `ARCHITECTURE.md` (commit `9d0cb93`).
- `docs:` add `CONSISTENCY.md` cross-cutting conventions (commit `45f809e`).
- `docs:` add `REPO_STATUS.md` living status doc (commit `98457e7`).
- `docs:` add `CHANGELOG.md` (this file).
- `docs:` prepare public README and ignore internal prompts/docs for open-source publishing.
- `docs:` merge the remote MIT license and update the public README license note.

### Scaffolding

- `chore:` scaffold project structure — directories, lint/format/test configs, Makefile, CI workflow, smoke test (commit `49b4656`).

### Prompt packs

- `docs:` prompt pack scaffolding and template — `prompts/README.md`, `_template/`, and the historical `bootstrap/INDEX.md` (commit `ce25fa3`).
- `docs:` first prompt pack for `memory-monitor-mvp` — eight task prompts plus `BREAKDOWN.md` and `INDEX.md` (commit `94c0e7e`).
- `docs:` add `app-dashboard` prompt pack for the native dashboard, status helper, app icon, docs, and verification workstream.

### Bootstrap closeout

- `docs:` backfill final commit hashes into `prompts/bootstrap/INDEX.md` and `CHANGELOG.md`.

### Feature: memory-monitor-mvp

- `feat(log):` JSONL logger with TEST_NOW honoring, escape-safe values, numeric pass-through, lazy parent-dir creation. Real-device fixtures captured (macOS 26.1 build 25B78). Discovered `memory_pressure(8)` is allocation-only — corrected primitives to `sysctl kern.memorystatus_vm_pressure_level / kern.memorystatus_level`, `vm_stat`, `sysctl vm.swapusage` (commit `4ff0e07`).
- `feat(pressure):` parser for the four sysctl/`vm_stat` outputs with defensive parsing, stub-able `_pressure::_invoke_external`, and pure decision functions `pressure::is_red`, `pressure::swap_in_use`.
- `feat(state):` cooldown-aware state file manager with atomic writes, schema-version field, structural-corruption warn, and override hooks (`MPM_STATE_PATH`, `TEST_NOW`).
- `feat(notify):` osascript notification driver with AppleScript escaping; `terminal-notifier` opt-in fallback; `stderr` backend for tests; every attempt logged.
- `feat(check):` entrypoint wires sample → debounce → notify. Validated against all five integration scenarios (normal, critical-once, critical-cooldown, swap-only, both-together).
- `feat(launchd):` plist template + `scripts/install.sh` (with `--dry-run`/`--force`) + `scripts/uninstall.sh` (with `--purge`). Rendered plist passes `plutil -lint` with the path-with-spaces repo location.
- **End-to-end shipped:** real `launchctl bootstrap` succeeded on macOS 26.1; first launchd-driven tick fired one swap_in_use notification (existing 2782 MiB swap on the device), second tick suppressed under cooldown. Install / install-noop / `--force` / uninstall / uninstall-idempotent all verified.
- `docs:` align README and REPO_STATUS with shipped v1.

### Feature: app-dashboard

- `feat(status):` add `scripts/status.sh` and `make status` for checking whether the launchd agent is installed, loaded, and writing logs.
- `feat(app):` add a native AppKit dashboard wrapper, deterministic generated app icon, and `make app` build target.
- `test(app):` add a build smoke test for the native dashboard app bundle.
- `fix(app):` add derived health status, launchd log visibility, app-level root/script validation, safer app build output handling, and clearer dashboard documentation.

### Fixes

- `fix(config):` replace executable user-config sourcing with strict `KEY=value` parsing and startup validation for numeric, backend, and path settings.
- `fix(state):` add persisted `swap_active` state so swap alerts fire on inactive → active transitions rather than repeating every cooldown while swap remains in use.
- `fix(check):` fail ticks on malformed primary pressure-level output, handle notification backend failures without aborting the whole check, record failed notification attempts for cooldown, and coalesce red+swap incidents into one notification.
- `fix(uninstall):` constrain `--purge` to default app-owned state/log paths and refuse root/sudo install or uninstall.
- `fix(notify):` pass notification title/body/sound to `osascript` as argv instead of interpolating user data into AppleScript source.
- `fix(log):` create log files with mode `0644` and refuse symlinked log targets.
- `test:` add config and install dry-run tests; expand pressure, state, notify, and entrypoint tests for audit regressions.
- `docs:` align CLAUDE, AGENTS, ARCHITECTURE, CONSISTENCY, README, REPO_STATUS, and the memory-monitor prompt pack with the shipped sysctl-based implementation and audit fixes.
- `fix(security):` reject sudo/root before user-facing scripts source config, preserve pre-existing log modes, reject unsafe custom log/state targets, and use `mktemp` for state/plist temp files.
- `fix(state):` parse documented pretty JSON state files without losing alert timestamps and warn on truncated state structures.
- `fix(pressure):` fail a tick on malformed swap output instead of logging a misleading `swap_used_mib:0` sample.
- `fix(ux):` rename the standalone swap notification to "Swap in use" so first-observed active swap is not described as a definite transition.
- `test:` cover invalid-config help paths, unsafe config targets, pretty state JSON, preserved log modes, and malformed swap output.
- `docs:` update README notification recovery notes for the resumed audit findings.
