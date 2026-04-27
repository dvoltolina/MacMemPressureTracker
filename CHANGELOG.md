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

### Scaffolding

- `chore:` scaffold project structure — directories, lint/format/test configs, Makefile, CI workflow, smoke test (commit `49b4656`).

### Prompt packs

- `docs:` prompt pack scaffolding and template — `prompts/README.md`, `_template/`, and the historical `bootstrap/INDEX.md` (commit `ce25fa3`).
- `docs:` first prompt pack for `memory-monitor-mvp` — eight task prompts plus `BREAKDOWN.md` and `INDEX.md` (commit `94c0e7e`).

### Bootstrap closeout

- `docs:` backfill final commit hashes into `prompts/bootstrap/INDEX.md` and `CHANGELOG.md` (this commit).
