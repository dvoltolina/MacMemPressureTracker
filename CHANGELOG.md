# Changelog

All notable changes to this repo are recorded here, grouped by date.

Format conventions:
- One H2 heading per calendar date (`## YYYY-MM-DD`).
- Within each date, group entries by area (`### Bootstrap`, `### Docs`, `### Scaffolding`, `### Feature: <name>`, `### Fixes`).
- Each entry is a bullet beginning with a Conventional Commits prefix matching the related commit (`feat:`, `fix:`, `chore:`, `docs:`, `refactor:`, `test:`).

---

## 2026-04-27

### Bootstrap

- `chore:` initial scaffold — empty repo with `.gitignore` and placeholder `README.md` (commit `579c118`).

### Docs

- `docs:` add `CLAUDE.md` top-level agent guidance (commit `19f1802`).
- `docs:` add `AGENTS.md` 10-step operating procedure (commit `bbe9c6d`).
- `docs:` add `ARCHITECTURE.md` (commit `9d0cb93`).
- `docs:` add `CONSISTENCY.md` cross-cutting conventions (commit `45f809e`).
- `docs:` add `REPO_STATUS.md` living status doc (commit `98457e7`).
- `docs:` add `CHANGELOG.md` (this file).
- `docs:` prepare public README and ignore internal prompts/docs for open-source publishing.

### Scaffolding

- `chore:` scaffold project structure — directories, lint/format/test configs, Makefile, CI workflow, smoke test (commit `49b4656`).

### Prompt packs

- `docs:` prompt pack scaffolding and template — `prompts/README.md`, `_template/`, and the historical `bootstrap/INDEX.md` (commit `ce25fa3`).
- `docs:` first prompt pack for `memory-monitor-mvp` — eight task prompts plus `BREAKDOWN.md` and `INDEX.md` (commit `94c0e7e`).

### Bootstrap closeout

- `docs:` backfill final commit hashes into `prompts/bootstrap/INDEX.md` and `CHANGELOG.md`.

### Feature: memory-monitor-mvp

- `feat(log):` JSONL logger with TEST_NOW honoring, escape-safe values, numeric pass-through, lazy parent-dir creation. Real-device fixtures captured (macOS 26.1 build 25B78). Discovered `memory_pressure(8)` is allocation-only — corrected primitives to `sysctl kern.memorystatus_vm_pressure_level / kern.memorystatus_level`, `vm_stat`, `sysctl vm.swapusage` (commit `4ff0e07`).
- `feat(pressure):` parser for the four sysctl/`vm_stat` outputs with defensive parsing, stub-able `_pressure::_invoke_external`, and pure decision functions `pressure::is_red`, `pressure::swap_in_use`.
- `feat(state):` cooldown-aware state file manager with atomic writes, schema-version field, structural-corruption warn, and override hooks (`MPM_STATE_PATH`, `TEST_NOW`).
- `feat(notify):` osascript notification driver with AppleScript escaping; `terminal-notifier` opt-in fallback; `stderr` backend for tests; every attempt logged.
- `feat(check):` entrypoint wires sample → debounce → notify. Validated against all five integration scenarios (normal, critical-once, critical-cooldown, swap-only, both-together).
- `feat(launchd):` plist template + `scripts/install.sh` (with `--dry-run`/`--force`) + `scripts/uninstall.sh` (with `--purge`). Rendered plist passes `plutil -lint` with the path-with-spaces repo location.
- **End-to-end shipped:** real `launchctl bootstrap` succeeded on macOS 26.1; first launchd-driven tick fired one swap_in_use notification (existing 2782 MiB swap on the device), second tick suppressed under cooldown. Install / install-noop / `--force` / uninstall / uninstall-idempotent all verified.
- `docs:` align README and REPO_STATUS with shipped v1.
