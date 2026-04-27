# 01-status-helper.md

## Task

Add a launchd status helper.

## Context

Users need a direct answer to "how do I know if it is running?" before and after the native app
wrapper exists. The helper should be usable by both humans and the dashboard app.

## Required Reading

- `CLAUDE.md`
- `AGENTS.md`
- `ARCHITECTURE.md`
- `CONSISTENCY.md`
- `REPO_STATUS.md`
- `scripts/install.sh`
- `scripts/uninstall.sh`
- `lib/config.sh`
- `lib/log.sh`

## Scope Boundaries

May modify:
- `scripts/status.sh`
- `tests/status_test.bats`
- `Makefile`
- `CHANGELOG.md`

Off-limits:
- `scripts/check_memory_pressure.sh`
- `scripts/install.sh`
- `scripts/uninstall.sh`
- `lib/pressure.sh`
- `lib/state.sh`
- `lib/notify.sh`

## Dependencies

None.

## Implementation Notes

- Use bash 3.2-compatible syntax.
- Refuse root/sudo early.
- Support default human output and `--json`.
- Report:
  - launchd loaded state using `launchctl print gui/$UID/com.dominic.memory-pressure-monitor`
  - plist installed state under `~/Library/LaunchAgents/`
  - resolved app log path
  - whether the app log exists
  - most recent sample/log line when present
  - state file path and whether it exists
  - config load status
- If config is invalid, keep reporting status with default paths and include the config error.
- Do not mutate state, logs, plist, or launchd.

## Acceptance Criteria

- [ ] `bash -n scripts/status.sh` passes.
- [ ] `scripts/status.sh` exits 0 and prints readable status.
- [ ] `scripts/status.sh --json` exits 0 and emits JSON.
- [ ] Status works when user config is invalid.
- [ ] Existing install/uninstall/check scripts are unchanged by this task.

## Documentation Requirement

- Add a dated `CHANGELOG.md` entry.
- README updates can be deferred to `03-docs-and-verification.md`.

## Commit Requirement

Commit independently when practical with message `feat(status): add monitor status helper`.
