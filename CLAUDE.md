# CLAUDE.md — Top-Level Agent Guidance

> Read this file first. Every agent working in this repo starts here.

---

## One-sentence project description

A personal macOS-only notification system that alerts the user when memory pressure enters the **red** state or the system begins using swap, implemented as a `launchd` user agent driving a small bash sampler.

---

## Tech stack and key dependencies

- **Language:** `bash` 3.2+ (the system shell on macOS — do not require bash 4+).
- **Scheduling:** `launchd` user agent (`~/Library/LaunchAgents/`).
- **Memory sampling:** `memory_pressure`, `vm_stat`, `sysctl vm.swapusage`.
- **Notifications:** `osascript -e 'display notification ...'` by default. `terminal-notifier` is an optional, opt-in alternative.
- **Tests:** [`bats-core`](https://github.com/bats-core/bats-core).
- **Lint/format:** `shellcheck`, `shfmt`.
- **CI:** GitHub Actions (`macos-latest` runner). Note: GitHub-hosted macOS runners may not faithfully reproduce real device memory pressure — treat CI as a smoke test, not a behavioral oracle.

There are **no third-party runtime dependencies**. End users should not have to `brew install` anything to use the tool. Development dependencies live behind a `make dev-deps` target (or equivalent installer doc).

---

## Repo layout (high level)

```
.
├── CLAUDE.md            ← you are here
├── AGENTS.md            ← full 10-step agent procedure
├── ARCHITECTURE.md      ← components, data flow
├── CONSISTENCY.md       ← naming, errors, logging, testing
├── REPO_STATUS.md       ← living status doc
├── CHANGELOG.md         ← dated record of all work
├── README.md            ← human-facing setup instructions
├── scripts/             ← user-facing entrypoints (install, run, uninstall)
├── lib/                 ← shared shell helpers, sourced by scripts
├── launchd/             ← plist templates + installer logic
├── tests/               ← bats-core test suite + fixtures
├── config/              ← default thresholds and intervals
├── .github/workflows/   ← CI pipeline
└── prompts/             ← prompt packs for future agent work
```

---

## Required reading order

For any non-trivial change, read in this order before editing:

1. `CLAUDE.md` (this file)
2. `AGENTS.md` — the full operating procedure
3. `REPO_STATUS.md` — current state, in-progress work, known limitations
4. `ARCHITECTURE.md` — relevant subsection for the area you're touching
5. `CONSISTENCY.md` — relevant cross-cutting rules
6. The **prompt file** assigned to the task (under `prompts/<workstream>/`)
7. Any source files explicitly listed in the prompt's *Required Reading* section

If the prompt's required reading conflicts with a top-level doc, **prefer the top-level doc** and flag the conflict in your final report.

---

## Commit and branch conventions

- **Default branch:** `main`. Direct commits to `main` are acceptable for personal-tool work; PRs are not required.
- **Branch naming (when used):** `<type>/<short-slug>`, e.g. `feat/swap-detection`, `fix/plist-paths`, `docs/architecture-update`.
- **Commit message format:** Conventional Commits prefix + short imperative summary. Body explains *why*, not *what*.
  - `feat:` new behavior
  - `fix:` bug fix
  - `chore:` scaffolding, configs, deps
  - `docs:` documentation only
  - `refactor:` no behavior change
  - `test:` test-only changes
- **Never** batch unrelated changes into one commit. If a single task touches docs and code, commit them separately when practical.
- **Never** skip hooks (`--no-verify`) without explicit user instruction.
- **Never** force-push `main`.

Every commit (and amendment) that lands behavior or scaffolding **must** also add a dated entry to `CHANGELOG.md`. This is non-negotiable per project rules.

---

## Common gotchas

> This list grows as agents discover sharp edges. Add to it; do not remove without justification.

- **Path with spaces.** The repo path contains a space (`personal software `) and a space in `activity monitor notifications`. Always quote `"$PATH"` in shell. Do not assume tooling handles unquoted paths gracefully.
- **bash 3.2 only.** macOS ships bash 3.2. Do not use `declare -A` (associative arrays), `mapfile`, or `${var,,}` lowercasing. Use POSIX-portable constructs.
- **`memory_pressure` output format.** The CLI's output format is undocumented and has changed across macOS versions. Parse defensively — see `lib/pressure.sh` (when implemented) for the canonical parser. Add fixture files under `tests/fixtures/` for any new format encountered.
- **`launchd` plist paths must be absolute.** Relative paths silently fail. The installer renders the plist from a template and substitutes the absolute repo path at install time.
- **Notification rate-limiting.** `osascript` notifications can be coalesced or dropped by the system if posted too frequently. Debounce at the application layer; do not rely on `launchd`'s `StartInterval` alone.
- **Do not read `/var/log/system.log`.** It requires elevated permissions and is not the source of truth for memory pressure. Use `memory_pressure` and `vm_stat` only.
- **Time zones.** All timestamps in logs and state files are local time, ISO 8601 with offset (e.g. `2026-04-27T08:45:00-07:00`). Do not use UTC unless explicitly requested.
- **No remote yet.** This repo has no `origin`. Push instructions in agent procedures are no-ops until a remote is added. Document this where it matters; do not silently skip.

---

## Pointer to the full procedure

`AGENTS.md` contains the complete 10-step operating procedure all agents (other than the bootstrap agent) must follow. Read it before any non-trivial change.

---

## When in doubt

- Make the **safest reasonable assumption** and document it in `REPO_STATUS.md` under "Open Questions" or in the agent's final report.
- Ask the user only when ambiguity could cause data loss, security issues, destructive changes, or major product-direction changes.
- Prefer reversible actions. Prefer narrower scope.
