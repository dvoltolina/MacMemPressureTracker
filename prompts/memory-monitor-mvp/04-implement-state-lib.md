# 04-implement-state-lib.md

## Task

Implement `lib/state.sh` exposing `state::should_alert <kind>` and `state::record_alert <kind>` against `state/last_alert.json`, with cooldown semantics keyed by `MPM_RED_COOLDOWN_SECONDS` and `MPM_SWAP_COOLDOWN_SECONDS`.

## Context

The debounce layer. Without it, every red sample fires a new notification — quickly intolerable. This module owns the on-disk state file lifecycle, including initial creation and corruption recovery.

## Required Reading

- `CLAUDE.md`
- `AGENTS.md`
- `ARCHITECTURE.md` (the "Components" and "Data model" sections, especially `state/last_alert.json` schema)
- `CONSISTENCY.md` (the "Function naming", "Date and time", "Configuration" sections)
- `config/defaults.sh`
- `lib/log.sh` (already implemented in task 02 — read its API only; do not modify)

## Scope Boundaries

May modify:
- `lib/state.sh` (new file)
- `tests/state_test.bats` (new file)
- `CHANGELOG.md`

Off-limits:
- `lib/log.sh` (exists; read-only here).
- All other `lib/` files, all `scripts/`, all `launchd/`.

## Dependencies

`02-implement-log-lib.md` — this module logs through `lib/log.sh`.

## Implementation Notes

- `lib/state.sh` is **sourced**, not executed.
- Public API:
  - `state::should_alert <kind>` — `kind ∈ {red_pressure, swap_in_use}`. Exit 0 if cooldown has elapsed, 1 if still within cooldown.
  - `state::record_alert <kind>` — writes a fresh timestamp for `kind`. Creates the state file if missing.
  - `state::path` — prints the resolved state file path (used by `scripts/uninstall.sh --purge`).
- State file location: `<repo-root>/state/last_alert.json` by default; override via `MPM_STATE_PATH`.
- File format: per `ARCHITECTURE.md`. `schema=1`. `last_alert.<kind>` is `null` until first write.
- Implementation tactic for read/write without `jq`:
  - Use `awk` to read a single field given a key path. Document the regex used.
  - Use `printf` to write the file from scratch on every change (the file is tiny — write-then-rename for atomicity).
- Time math:
  - Use `date +%s` for "now" in epoch seconds.
  - Convert ISO 8601 stored timestamps back to epoch via `date -j -f "%Y-%m-%dT%H:%M:%S%z" "<ts>" +%s`. Strip the colon from the offset before passing to `date -j -f` (macOS's BSD `date` accepts `+0700` not `+07:00`).
  - Honor `TEST_NOW` env var: if set (epoch seconds), use it instead of `date +%s`.
- Corruption handling: if the JSON cannot be parsed, log a warning via `lib/log.sh` and treat as "no prior alerts". Overwrite on next `record_alert`.
- Use atomic writes: write to `<state>.tmp` then `mv` over the target. Both files use perms `0644`.

## Acceptance Criteria

- [ ] `make fmt-check` passes
- [ ] `make lint` passes
- [ ] `bats tests/state_test.bats` covers:
  - missing state file → `should_alert` returns 0 (allow)
  - just-recorded alert → `should_alert` returns 1 (suppress) within cooldown
  - cooldown elapsed (controlled via `TEST_NOW`) → `should_alert` returns 0
  - corrupted JSON file → `should_alert` returns 0 and logs a warning
  - `state::path` returns the expected resolved path under `MPM_STATE_PATH` override
  - atomic write: a `.tmp` file is not left behind on success
- [ ] `make test` passes overall
- [ ] `lib/state.sh` is not executable

## Documentation Requirement

- Add a dated `CHANGELOG.md` entry: `feat(state): cooldown-aware state file manager`.
- If you discover the schema needs a change, update `ARCHITECTURE.md` and bump the schema version. Document the migration story in `lib/state.sh::state::migrate`.

## Commit Requirement

Commit independently with message `feat(state): cooldown-aware state file manager`.
