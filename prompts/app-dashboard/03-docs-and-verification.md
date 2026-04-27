# 03-docs-and-verification.md

## Task

Document and verify the app dashboard.

## Context

After adding a status helper and app wrapper, user-facing docs must explain how to know whether the
monitor is running and how to launch the app.

## Required Reading

- `CLAUDE.md`
- `AGENTS.md`
- `README.md`
- `REPO_STATUS.md`
- `CHANGELOG.md`
- `prompts/app-dashboard/INDEX.md`

## Scope Boundaries

May modify:
- `README.md`
- `CHANGELOG.md`
- `REPO_STATUS.md`

Off-limits:
- Runtime source files except for audit fixes.

## Dependencies

Depends on `01-status-helper.md` and `02-native-dashboard-app.md`.

## Implementation Notes

- Add concise instructions for:
  - `scripts/status.sh`
  - `scripts/status.sh --json`
  - `make app`
  - opening `build/Memory Pressure Monitor.app`
- Document known limitations:
  - app bundle is tied to the repo path at build time
  - notification permission is still macOS-controlled
  - dev tools may still be needed for full test suite

## Acceptance Criteria

- [ ] README explains how to check running status.
- [ ] README explains how to build/open the app.
- [ ] CHANGELOG has a dated entry under the current date.
- [ ] REPO_STATUS mentions the dashboard if local/private docs are being maintained.

## Documentation Requirement

This task is documentation-focused.

## Commit Requirement

Commit with implementation docs or separately if practical.
