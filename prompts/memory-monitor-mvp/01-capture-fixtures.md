# 01-capture-fixtures.md

## Task

Capture real-device output of `memory_pressure -Q`, `vm_stat`, and `sysctl vm.swapusage` from the user's macOS machine and commit them as test fixtures.

## Context

Every parser in `lib/pressure.sh` (task 03) is tested against fixture files so tests can run anywhere — including CI runners where `memory_pressure` may produce non-realistic output. Without fixtures, the parser is untestable. We need fixtures for at least the user's current macOS version, covering the three pressure zones and both swap states.

## Required Reading

- `CLAUDE.md`
- `AGENTS.md`
- `ARCHITECTURE.md` (the "Components" subsection on `lib/pressure.sh`)
- `CONSISTENCY.md` (the "Testing" and "File and directory naming" sections)
- `prompts/memory-monitor-mvp/BREAKDOWN.md`

## Scope Boundaries

May modify:
- `tests/fixtures/memory_pressure_normal.txt`
- `tests/fixtures/memory_pressure_warn.txt`
- `tests/fixtures/memory_pressure_red.txt`
- `tests/fixtures/vm_stat_macos<N>.txt` (where `<N>` is the user's macOS major version)
- `tests/fixtures/sysctl_swapusage_inactive.txt`
- `tests/fixtures/sysctl_swapusage_active.txt`
- `tests/fixtures/.gitkeep` (delete once real fixtures exist)
- `CHANGELOG.md`

Off-limits:
- Anything outside `tests/fixtures/`.
- All `lib/`, `scripts/`, `launchd/` content.

## Dependencies

`None`.

## Implementation Notes

- Run `sw_vers -productVersion` and embed the **major** version in `vm_stat` and `memory_pressure` fixture filenames if behavior differs across versions. If you only have one version available, document that in the `CHANGELOG.md` entry; future agents add more later.
- For "red" memory pressure, generate load with a tool like `stress-ng --vm 2 --vm-bytes 80% -t 60s` (install via Homebrew) **on a test session, not the user's primary work session**. If unavailable, write a small `python3 -c "x = bytearray(8*1024**3)"` to allocate enough memory to push the system into red. Ask the user before running anything that could destabilize their session.
- For active swap, allocate enough to exceed physical RAM. Be patient — swap takes a few seconds to start.
- Fixtures must be **plain text**, exactly as the command produced them, no editing.
- File names use `snake_case` per `CONSISTENCY.md`.

## Acceptance Criteria

- [ ] All six fixtures exist and contain non-empty real output.
- [ ] Filenames match the patterns above.
- [ ] No additional ad-hoc files committed.
- [ ] `make test` still passes (the existing smoke test does not depend on fixtures).
- [ ] `tests/fixtures/.gitkeep` deleted if real files now make it redundant.

## Documentation Requirement

- Add a dated `CHANGELOG.md` entry under today's H2 in a `### Feature: memory-monitor-mvp` group: `test: capture memory pressure / vm_stat / swap fixtures`.
- Note in `REPO_STATUS.md` "Open Questions" if any of the three zones could not be captured (e.g. could not safely reproduce red on a primary device).

## Commit Requirement

Commit independently with message `test: capture memory pressure and swap fixtures`. Group with task 02 only if 02 is also a tiny change and was completed in the same session.
