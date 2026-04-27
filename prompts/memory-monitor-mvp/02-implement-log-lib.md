# 02-implement-log-lib.md

## Task

Implement `lib/log.sh` providing `log::info`, `log::warn`, `log::error` that emit one JSONL record per call to a configurable log file.

## Context

Every other library uses `lib/log.sh` for diagnostics. Implementing it first means downstream tasks can lean on a real logger instead of stubbing. The format is fixed in `CONSISTENCY.md`; implement to that exact shape.

## Required Reading

- `CLAUDE.md`
- `AGENTS.md`
- `ARCHITECTURE.md` (the "Components" subsection on `lib/log.sh`)
- `CONSISTENCY.md` (the "Logging", "Function naming", "Variable conventions", "Error handling", "Date and time" sections)
- `config/defaults.sh` (for `MPM_LOG_PATH`)

## Scope Boundaries

May modify:
- `lib/log.sh` (new file)
- `tests/log_test.bats` (new file)
- `CHANGELOG.md`

Off-limits:
- Any other `lib/` file.
- Any `scripts/`, `launchd/`, top-level doc except `CHANGELOG.md`.

## Dependencies

`None`.

## Implementation Notes

- `lib/log.sh` is **sourced**, never executed. Do not set `set -Eeuo pipefail` at file scope — that affects the caller. Do not `chmod +x`.
- API:
  - `log::info <event> [k=v ...]`
  - `log::warn <event> [k=v ...]`
  - `log::error <event> [k=v ...]`
- `event` is the snake_case stable identifier. Additional `key=value` pairs become JSON fields.
- Output schema (one line):
  ```
  {"ts":"<iso8601>","level":"<level>","event":"<event>",<extra-fields...>}
  ```
- Generate `ts` via `date "+%Y-%m-%dT%H:%M:%S%z"` then `sed 's/\([+-][0-9][0-9]\)\([0-9][0-9]\)$/\1:\2/'`.
- Honor `TEST_NOW` env var: if set, use it verbatim as `ts` (used by tests).
- Honor `MPM_LOG_PATH`. Create parent directory lazily. Append, never overwrite.
- Escape values that contain `"` or `\`. JSON-escape via a small helper — do **not** depend on `jq`.
- Emit to stderr in addition to the log file when `MPM_LOG_TEE_STDERR=1` (tests use this).

## Acceptance Criteria

- [ ] `make fmt-check` passes
- [ ] `make lint` passes (no shellcheck warnings)
- [ ] `bats tests/log_test.bats` covers:
  - emits one valid JSON object per call
  - includes `ts`, `level`, `event`, and any extra fields
  - escapes `"` and `\` correctly in values
  - respects `TEST_NOW`
  - creates the log directory if missing
  - tees to stderr when `MPM_LOG_TEE_STDERR=1`
- [ ] `make test` passes overall
- [ ] `lib/log.sh` is **not** executable

## Documentation Requirement

- Add a dated `CHANGELOG.md` entry: `feat(log): JSONL logger with level helpers`.
- No top-level doc updates expected; behavior matches what is already documented in `ARCHITECTURE.md` and `CONSISTENCY.md`.

## Commit Requirement

Commit independently with message `feat(log): JSONL logger with level helpers`.
