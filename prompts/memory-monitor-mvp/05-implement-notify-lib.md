# 05-implement-notify-lib.md

## Task

Implement `lib/notify.sh` exposing `notify::send <title> <body> [sound]` driving `osascript` by default, with a `stderr` fallback for tests and an opt-in `terminal-notifier` backend.

## Context

The user-facing layer. Notifications must be reliable, debounce-aware (caller's responsibility — task 04), and degrade gracefully when permissions are missing or no backend is available.

## Required Reading

- `CLAUDE.md`
- `AGENTS.md`
- `ARCHITECTURE.md` (the "Components" subsection on `lib/notify.sh`)
- `CONSISTENCY.md` (the "Variable conventions", "Error handling" sections)
- `config/defaults.sh` (for `MPM_NOTIFICATION_BACKEND`, `MPM_NOTIFICATION_SOUND`)
- `lib/log.sh` (read-only)

## Scope Boundaries

May modify:
- `lib/notify.sh` (new file)
- `tests/notify_test.bats` (new file)
- `CHANGELOG.md`

Off-limits:
- All other `lib/`, all `scripts/`, all `launchd/`.

## Dependencies

`02-implement-log-lib.md` — `notify::send` logs every attempt.

## Implementation Notes

- `lib/notify.sh` is **sourced**, not executed.
- Public API:
  - `notify::send <title> <body> [sound]` — fires a notification via the configured backend. Returns 0 on success, non-zero on backend error.
- Backends, switched on `MPM_NOTIFICATION_BACKEND`:
  - `osascript` (default): `osascript -e 'display notification "<body>" with title "<title>"' [sound name "<sound>"]`. Escape `"` and `\` in title/body.
  - `terminal-notifier`: only used if the binary is on `PATH`. Otherwise log a warn and fall through to `osascript`.
  - `stderr` (tests only): print a single line `notify: title=<...> body=<...> sound=<...>` to stderr.
- Always log via `log::info` with `event=notify_attempt` (and `event=notify_failed` on non-zero from the backend) — captures backend, title, and exit code (NOT the body, which may include user content).
- Escaping: the `osascript` path is the highest-risk for command injection. Pass title and body via separate `-e` strings or wrap them with `' '` and replace any single quote inside with `' & quote & '`. Do not concatenate untrusted input into the AppleScript without escaping. Add a unit test that includes `"`, `\`, and `'` in title and body.
- Sound: only emit `sound name "..."` if the third argument is non-empty.

## Acceptance Criteria

- [ ] `make fmt-check` passes
- [ ] `make lint` passes
- [ ] `bats tests/notify_test.bats` covers:
  - `stderr` backend prints expected line and returns 0
  - title/body containing `"`, `\`, `'` are escaped (tested via the `stderr` backend by asserting the rendered AppleScript string)
  - `osascript` backend invocation is exercised through a stubbed `osascript` on `PATH` that records its argv to a temp file
  - missing `terminal-notifier` falls back to `osascript` with a logged warning
  - `notify::send` returns non-zero when the backend stub returns non-zero
- [ ] `make test` passes overall
- [ ] `lib/notify.sh` is not executable

## Documentation Requirement

- Add a dated `CHANGELOG.md` entry: `feat(notify): osascript notification driver with stderr fallback`.

## Commit Requirement

Commit independently with message `feat(notify): osascript notification driver with stderr fallback`.
