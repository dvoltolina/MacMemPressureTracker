# CONSISTENCY.md

Cross-cutting rules every agent must follow. When a rule here conflicts with a prompt's *Implementation Notes*, **prefer this doc** unless the prompt explicitly cites and overrides a rule.

---

## File and directory naming

- Shell scripts in `scripts/` end in `.sh` and have an executable bit (`chmod +x`).
- Library files in `lib/` end in `.sh`, **not** executable, designed to be `source`d.
- Test files in `tests/` end in `.bats`, named `<unit>_test.bats`.
- Fixture files in `tests/fixtures/` are plain text snapshots of real command output, named `<command>_<scenario>.txt` (e.g. `memory_pressure_red.txt`).
- launchd plist templates in `launchd/` use the suffix `.plist.tmpl`.
- Use `kebab-case` for file names, never `snake_case` or `camelCase`. Exception: `bats` test files use `snake_case` to match the function-under-test convention.

---

## Function naming (shell)

- Library functions are namespaced: `<module>::<verb>`, e.g. `pressure::sample`, `state::record_alert`.
- Internal helpers are prefixed with `_`: `_pressure::parse_block`.
- Use `snake_case` within names. Verbs over nouns. No abbreviations except well-known ones (`pct`, `mib`, `id`).

---

## Variable conventions (shell)

- `local` every function-scoped variable.
- Quote every expansion: `"$var"`, `"${arr[@]}"`, `"$(cmd)"`.
- Read-only constants are `UPPER_SNAKE_CASE` and declared `readonly`.
- Sentinel return values from "pure" functions are stdout; status codes are reserved for true success/failure.
- Never rely on `$IFS`. Always set explicitly when splitting.
- No `eval`. No backticks. Use `$(...)`.

---

## Error handling

- Every script begins with:
  ```sh
  #!/bin/bash
  set -Eeuo pipefail
  IFS=$'\n\t'
  ```
- Trap `ERR` to log line number + command before exiting:
  ```sh
  trap 'log::error "exit on line $LINENO: $BASH_COMMAND"' ERR
  ```
- Errors at the **boundary** (parsing external command output, reading user files, network — n/a here) get explicit handling. Errors in internal logic crash via `set -e`.
- Never swallow errors with `|| true` unless paired with a comment explaining why.

---

## Logging

- One module: `lib/log.sh`. All other code logs through it.
- Three levels: `info`, `warn`, `error`. No `debug` in v1 (add later if needed).
- Output format is **JSONL**: one JSON object per line, fields in this order: `ts`, `level`, `event`, then arbitrary key/values.
- Use `event` as a stable machine identifier (snake_case verb-phrase): `sample_taken`, `alert_fired`, `state_corrupted`. Human-readable detail goes in additional fields, never in `event`.
- Never log secrets. Never log full command lines containing user paths beyond the repo root.

Example:
```json
{"ts":"2026-04-27T08:45:00-07:00","level":"info","event":"sample_taken","zone":"red","free_pct":4.2}
```

---

## Testing

- Framework: `bats-core`. Each library file has a sibling `tests/<file>_test.bats`.
- Tests must run **without** real-device side effects: no `launchctl`, no real `osascript`, no real `memory_pressure`. Stub or fixture every external dependency.
- Fixtures are committed under `tests/fixtures/` and represent **real** captured output from real macOS versions. Annotate the macOS version in the filename if behavior diverges across versions (e.g. `vm_stat_macos14.txt`).
- A passing test suite is required before any commit that touches `scripts/`, `lib/`, or `launchd/`.
- `tests/smoke_test.bats` always exists and asserts that all library files source cleanly. CI runs it on every PR.

---

## Date and time

- All on-disk timestamps: ISO 8601 with explicit offset, **local time**, e.g. `2026-04-27T08:45:00-07:00`.
- Never store UTC unless explicitly requested.
- Generate timestamps via `date "+%Y-%m-%dT%H:%M:%S%z"` and post-process the offset to insert the colon (`-0700` → `-07:00`) using `sed 's/\([+-][0-9][0-9]\)\([0-9][0-9]\)$/\1:\2/'`.
- `bats` tests freeze time via a `TEST_NOW` env var read by `lib/log.sh` and `lib/state.sh`.

---

## ID generation

- The only ID in this system is the launchd label: `com.dominic.memory-pressure-monitor`.
- Do not introduce UUIDs, ULIDs, or numeric IDs without justification.

---

## Configuration

- Defaults live in `config/defaults.sh` as a sourceable file of `readonly` assignments.
- User overrides live in `~/.config/memory-pressure-monitor/config.sh` (the same format) and are sourced **after** defaults.
- All config keys are `UPPER_SNAKE_CASE` and prefixed `MPM_` (e.g. `MPM_INTERVAL_SECONDS`, `MPM_RED_COOLDOWN_SECONDS`).
- Validate every config value at script start. Bail with a clear error if a value is missing or malformed.

---

## Money / currency / localization / accessibility

- **Not applicable** to this repo. Documented here so future agents do not invent rules.

---

## Documentation style

- Markdown wraps at ~100 columns where reasonable. Do not hard-wrap inside code fences.
- Code fences declare the language (` ```sh `, ` ```json `, ` ```mermaid `).
- Cross-doc links use root-relative paths: `[ARCHITECTURE.md](ARCHITECTURE.md)`. Do not link to specific line numbers; they rot.
- Every doc has a single H1 matching its filename (`# CONSISTENCY.md`).
- Use **bold** for the rule itself and prose for the explanation. Use lists for enumerations, not for prose.

---

## Commits and CHANGELOG

- See `CLAUDE.md` for commit message conventions.
- Every commit that changes behavior or scaffolding gets a `CHANGELOG.md` entry under today's date heading. Doc-only commits also get an entry.
- Do not "fix typos" silently; one commit per logical change.
