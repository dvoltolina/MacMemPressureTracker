# 03-implement-pressure-lib.md

## Task

Implement `lib/pressure.sh` exposing `pressure::sample` (composite reader), `pressure::is_red` (decision), and `pressure::swap_in_use` (boolean given a `sysctl vm.swapusage` block).

## Context

This is the metric-parsing layer. It transforms raw command output into a normalized record so the rest of the system never has to re-parse. Without this, every change risks reinventing brittle parsing.

## Required Reading

- `CLAUDE.md`
- `AGENTS.md`
- `ARCHITECTURE.md` (the "Components" subsection on `lib/pressure.sh`, the "Failure modes" table)
- `CONSISTENCY.md` (the "Function naming", "Variable conventions", "Error handling", "Testing" sections)
- `prompts/memory-monitor-mvp/BREAKDOWN.md`
- All files in `tests/fixtures/` (committed by task 01)

## Scope Boundaries

May modify:
- `lib/pressure.sh` (new file)
- `tests/pressure_test.bats` (new file)
- `CHANGELOG.md`

Off-limits:
- Any other `lib/` file (including `lib/log.sh`).
- Any `scripts/`, `launchd/`, top-level doc except `CHANGELOG.md`.

## Dependencies

`01-capture-fixtures.md` — fixtures must exist before this task can write tests.

## Implementation Notes

- `lib/pressure.sh` is **sourced**, not executed. Do not set `set -Eeuo pipefail` at file scope.
- Parser is **pure**: every public function reads from a stdin handle or argument, never invokes `memory_pressure`/`vm_stat`/`sysctl` itself. A small wrapper, `pressure::_invoke_external`, is the *only* function that runs real binaries; tests stub it out.
- Public API:
  - `pressure::sample` — internally calls `pressure::_invoke_external`, parses, prints one JSON line: `{"zone":"normal|warn|red","free_pct":<num>,"compressed_pct":<num>,"swap_used_mib":<num>}`.
  - `pressure::is_red <json-line>` — exit 0 if `zone == "red"`, else 1. No stdout.
  - `pressure::swap_in_use <json-line>` — exit 0 if `swap_used_mib >= MPM_SWAP_THRESHOLD_MIB`, else 1.
  - `pressure::parse_memory_pressure` — reads `memory_pressure -Q`-style output from stdin, prints `zone=<...> free_pct=<...> compressed_pct=<...>` as space-separated `k=v`.
  - `pressure::parse_swap` — reads `sysctl vm.swapusage`-style output from stdin, prints `swap_used_mib=<...>`.
- Use only POSIX text tools: `awk`, `sed`, `grep`. No `jq`.
- Map `memory_pressure` zone strings to canonical labels:
  - "Normal" → `normal`
  - "Warning" → `warn`
  - "Critical" → `red`
  - anything else → log warn via stderr (caller logs proper) and treat as `normal` so we don't notify on noise.
- Defensive parsing: every regex tolerates extra whitespace and case differences.
- Document in a header comment which macOS major versions the parser was tested against (matches the fixtures).

## Acceptance Criteria

- [ ] `make fmt-check` passes
- [ ] `make lint` passes
- [ ] `bats tests/pressure_test.bats` covers:
  - each fixture in `tests/fixtures/memory_pressure_*.txt` parses to the expected zone
  - each fixture in `tests/fixtures/sysctl_swapusage_*.txt` parses to the expected MiB value
  - `pressure::is_red` correctly classifies all three zones
  - `pressure::swap_in_use` honors `MPM_SWAP_THRESHOLD_MIB`
  - malformed input returns non-zero with no stdout
- [ ] `make test` passes overall
- [ ] `lib/pressure.sh` is not executable

## Documentation Requirement

- Add a dated `CHANGELOG.md` entry: `feat(pressure): add memory and swap parsers`.
- No top-level doc changes expected.

## Commit Requirement

Commit independently with message `feat(pressure): add memory and swap parsers`.
