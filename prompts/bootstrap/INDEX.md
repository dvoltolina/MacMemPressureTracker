# INDEX — bootstrap (historical)

> This pack is **historical**. It documents the bootstrap work that initialized the repo so future agents can understand how decisions were made. Do not re-run the tasks here.

## Summary

Initialized the repo per the Bootstrap Agent procedure. Established foundational documentation, scaffolding, prompt-pack conventions, and the first real prompt pack (`memory-monitor-mvp`).

## Outcome

The repo at the end of bootstrap contains:

- `CLAUDE.md`, `AGENTS.md`, `ARCHITECTURE.md`, `CONSISTENCY.md`, `REPO_STATUS.md`, `CHANGELOG.md`, `README.md`.
- `Makefile`, `.editorconfig`, `.shellcheckrc`, `.shfmt`, `.env.example`, `.gitignore`.
- Empty-but-tracked `scripts/`, `lib/`, `launchd/`, `tests/fixtures/` (via `.gitkeep`), plus `config/defaults.sh`.
- `tests/smoke_test.bats` covering the scaffold itself.
- `.github/workflows/ci.yml` for `macos-latest` running `make fmt-check lint test`.
- `prompts/README.md`, `prompts/_template/{INDEX,EXAMPLE_TASK}.md`, this file.
- `prompts/memory-monitor-mvp/` containing the first real prompt pack and its `BREAKDOWN.md`.

## Bootstrap commits (chronological)

| Hash | Message |
| --- | --- |
| `579c118` | `chore: initial scaffold` |
| `19f1802` | `docs: add CLAUDE.md top-level agent guidance` |
| `bbe9c6d` | `docs: add AGENTS.md operating procedure` |
| `9d0cb93` | `docs: add ARCHITECTURE.md` |
| `45f809e` | `docs: add CONSISTENCY.md cross-cutting conventions` |
| `98457e7` | `docs: add REPO_STATUS.md living status doc` |
| `6d85f5e` | `docs: add CHANGELOG.md` |
| `49b4656` | `chore: scaffold project structure` |
| `ce25fa3` | `docs: prompt pack scaffolding and template` |
| `94c0e7e` | `docs: first prompt pack for memory-monitor-mvp` |

## Decisions worth preserving

1. **Bash + launchd over Swift / Python.** Zero dependencies, native, simplest install. Reconsidered if shell becomes unwieldy.
2. **`osascript` over `terminal-notifier` by default.** No Homebrew install required for end-user.
3. **JSONL log format.** Greppable + machine-parseable without invoking `jq`.
4. **No remote at bootstrap time.** Push steps are documented as no-ops; a future agent adds the remote when the user provides one.
5. **bash 3.2 portability.** macOS ships bash 3.2; do not require bash 4 features.
6. **State file at `state/last_alert.json` (gitignored).** Schema-versioned for forward compatibility.
7. **Notification permission lives with the user.** No automated grant path.

## Audit cadence

Audit agents are skipped during bootstrap (per Step 8 of the Bootstrap procedure). Audits begin after the first real feature ships from `memory-monitor-mvp`.
