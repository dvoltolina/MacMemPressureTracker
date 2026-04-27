# REPO_STATUS.md

> Living status doc. Update this file whenever a meaningful change lands.

---

## Current branch

`main`

## Last meaningful commit

`docs: add CONSISTENCY.md cross-cutting conventions` (this status doc commit will follow).

---

## Implemented features

_None yet — the repo is bootstrapped only._

The first real feature lives in `prompts/memory-monitor-mvp/` and has not been executed.

---

## In-progress workstreams

- **memory-monitor-mvp** — prompt pack drafted; implementation pending. See `prompts/memory-monitor-mvp/INDEX.md` (created in a later commit in this same bootstrap series).

---

## Known limitations

- **No remote git origin yet.** All checkpoint/push steps in `AGENTS.md` are local-only until the user adds a remote. Document this in any final report.
- **No CI runs yet.** GitHub Actions workflow is committed but cannot run until the repo is pushed to GitHub.
- **No real implementation.** Lint and tests have nothing meaningful to check beyond a smoke test.
- **`memory_pressure` output format is undocumented** and has changed across macOS versions. The first implementation prompt must capture fixtures from the user's actual macOS version before parser work begins.
- **Notification permission** has to be granted manually by the user on first run. There is no automated way to grant it.

---

## Open follow-ups

1. Add a git remote (`origin`). Update this file once added.
2. Capture `memory_pressure -Q`, `vm_stat`, and `sysctl vm.swapusage` fixtures from the target macOS version. Save under `tests/fixtures/`.
3. Execute the `memory-monitor-mvp` prompt pack.
4. Begin audit cadence after the first real feature ships (per Bootstrap Step 8).
5. Decide on a long-term log rotation strategy (currently deferred to v2).

---

## Open questions

- **Default thresholds.** What pressure level constitutes "red" should be confirmed against the user's actual workload. The first prompt pack proposes `memory_pressure -Q` zone == `critical` as red, but this can be tuned.
- **Notification copy.** Final wording is decided in the implementation prompt; the bootstrap does not pre-commit to specific text.
- **Cooldown duration.** Defaults proposed as `MPM_RED_COOLDOWN_SECONDS=600` (10 min) and `MPM_SWAP_COOLDOWN_SECONDS=900` (15 min). Subject to user feedback.

---

## Bootstrap assumptions

These are assumptions made because the original project context did not specify. Confirm or revise before the first real implementation commit.

| # | Assumption | Why made | Risk if wrong |
|---|------------|----------|---------------|
| 1 | macOS-only, no Linux/Windows support | User said "MacBook" | None for v1; revisit if scope expands |
| 2 | Bash + `launchd` rather than Swift / Python | Zero-dependency, simplest, native | Heavier stacks may be revisited if shell becomes unwieldy |
| 3 | `osascript` notifications, not `terminal-notifier` | No third-party install required | None for v1; `terminal-notifier` documented as opt-in |
| 4 | `launchd` user agent (`gui/$UID`), not system daemon | No root needed; runs in user session | None — explicitly the right scope for a personal tool |
| 5 | No remote git origin at bootstrap time | None was provided | Push steps documented as no-ops until remote added |
| 6 | ISO 8601 + local offset for timestamps | Matches user's likely expectation; no UTC ambiguity | If user prefers UTC, change in `lib/log.sh` and `lib/state.sh` consistently |
| 7 | JSONL log format | Easy to grep and parse later if needed | Requires `jq` or similar to inspect; documented in CLAUDE.md |
| 8 | Bundle identifier `com.dominic.memory-pressure-monitor` | Single-user; user's name is Dominic per env | Change with care — affects the launchd label and uninstall step |

---

## Audit cadence

Audit agents are **skipped during bootstrap**. The cadence begins after the first real feature ships. See `AGENTS.md` Step 8 for what audits to run.
