# &lt;NN&gt;-&lt;verb&gt;-&lt;noun&gt;.md — example task

> Filename pattern: `NN-verb-noun.md`, where `NN` is a two-digit ordinal (`01`, `02`, ...) reflecting the recommended execution order within the pack. Delete this quote line.

## Task

Implement `lib/foo.sh` exposing `foo::bar()`, a pure function that takes a `vm_stat` fixture on stdin and returns a JSON line on stdout summarizing free/active/inactive page counts.

## Context

The first feature module needs a parser for `vm_stat` output. Splitting it out keeps the parser pure and testable independently from the launchd-driven sampler. Without this, every downstream change has to re-parse from scratch.

## Required Reading

- `CLAUDE.md`
- `AGENTS.md`
- `ARCHITECTURE.md` (the "Components" and "Data model" sections)
- `CONSISTENCY.md` (the "Function naming", "Variable conventions", and "Error handling" sections)
- `tests/fixtures/vm_stat_macos14.txt` (capture and commit this fixture if missing)

## Scope Boundaries

May modify:
- `lib/foo.sh` (new file)
- `tests/foo_test.bats` (new file)
- `tests/fixtures/vm_stat_macos14.txt` (new fixture, only if missing)

Off-limits:
- `scripts/*` — no entrypoints touched in this task.
- `lib/log.sh`, `lib/state.sh`, `lib/notify.sh` — different tasks.
- Any top-level doc except `CHANGELOG.md` and `REPO_STATUS.md`.

## Dependencies

`None`.

## Implementation Notes

- Follow `CONSISTENCY.md` Function naming: `foo::bar`, internal helpers `_foo::*`.
- Use only bash 3.2 constructs; no associative arrays.
- The function must read from stdin to remain testable without invoking real `vm_stat`.
- Output one JSON line via `printf` — do not depend on `jq`.
- Handle malformed input by returning non-zero and emitting nothing on stdout.
- Follow the `set -Eeuo pipefail` + `trap ERR` boilerplate from `CONSISTENCY.md` for any executable script (libraries are sourced and inherit caller settings — do not set them at file scope).

## Acceptance Criteria

- [ ] `make fmt-check` passes
- [ ] `make lint` passes (no `shellcheck` warnings)
- [ ] `bats tests/foo_test.bats` covers normal, malformed, and empty inputs
- [ ] `make test` passes overall
- [ ] `lib/foo.sh` is **not** executable (libraries are sourced, not run)
- [ ] No global state introduced; function is pure given its stdin

## Documentation Requirement

- Add a dated `CHANGELOG.md` entry under today's H2 in the `### Feature: <pack-name>` group.
- Update `REPO_STATUS.md` "Implemented features" if this completes a milestone.
- No top-level doc updates expected.

## Commit Requirement

Commit independently with message `feat(foo): add vm_stat parser`. Push after the commit lands.
