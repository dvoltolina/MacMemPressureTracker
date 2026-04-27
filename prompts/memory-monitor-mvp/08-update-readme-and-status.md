# 08-update-readme-and-status.md

## Task

Replace the placeholder install instructions in `README.md` with the real, working commands and update `REPO_STATUS.md` to mark the workstream complete.

## Context

The `README.md` shipped with the bootstrap declares the project status as "scaffolded — feature implementation pending". After tasks 01–07 land, that statement is outdated. This task closes the loop on documentation so a new user (or a future agent) sees an accurate first impression.

## Required Reading

- `CLAUDE.md`
- `AGENTS.md`
- `README.md` (current)
- `REPO_STATUS.md` (current)
- `scripts/install.sh`, `scripts/uninstall.sh` (for actual flag names and output)
- `prompts/memory-monitor-mvp/INDEX.md` (final-verification checklist)

## Scope Boundaries

May modify:
- `README.md`
- `REPO_STATUS.md`
- `CHANGELOG.md`

Off-limits:
- Any code under `lib/`, `scripts/`, `launchd/`.
- Any other top-level doc.

## Dependencies

`07-launchd-template-and-installer.md`.

## Implementation Notes

- Replace the "Status: scaffolded — feature implementation pending" badge in `README.md` with a current statement (e.g. "Status: v1 shipped").
- Update the "Quick start" section to reflect real `install.sh` flags (`--dry-run`, `--force`, etc.).
- Add a "First-run notification permission" subsection explaining macOS will prompt on first notification.
- Update `REPO_STATUS.md`:
  - Move `memory-monitor-mvp` from "In-progress workstreams" to "Implemented features".
  - Strike-through items in "Open follow-ups" that are now closed.
  - Add new follow-ups discovered during implementation (e.g. log rotation, Slack webhook).
  - Update "Bootstrap assumptions" — strike or annotate any that were validated in implementation.

## Acceptance Criteria

- [ ] `README.md` quick-start commands exactly match the actual scripts.
- [ ] `REPO_STATUS.md` reflects the post-MVP state.
- [ ] `make test` still passes.
- [ ] `make fmt-check` and `make lint` still pass (unchanged code).

## Documentation Requirement

- Add a dated `CHANGELOG.md` entry: `docs: align README and REPO_STATUS with shipped v1`.

## Commit Requirement

Commit independently with message `docs: align README and REPO_STATUS with shipped v1`.
