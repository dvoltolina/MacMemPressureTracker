# 07-launchd-template-and-installer.md

## Task

Author the launchd plist template and the install/uninstall scripts that render it, load it via `launchctl bootstrap`, and remove it cleanly on uninstall.

## Context

Without this task, the entrypoint built in task 06 only runs when invoked manually. This is the layer that makes the system actually monitor on a schedule. It is the most platform-coupled task in the pack — get it wrong and the agent silently does nothing or runs forever.

## Required Reading

- `CLAUDE.md`
- `AGENTS.md`
- `ARCHITECTURE.md` (the "Components" subsection on `launchd/...plist.tmpl` + the "Failure modes" table)
- `CONSISTENCY.md` (entire — installer touches files, perms, paths)
- `prompts/memory-monitor-mvp/BREAKDOWN.md`
- `scripts/check_memory_pressure.sh` (read-only)
- Apple's `launchd.plist(5)` man page (consult the user's local `man launchd.plist`)

## Scope Boundaries

May modify:
- `launchd/com.dominic.memory-pressure-monitor.plist.tmpl` (new file)
- `scripts/install.sh` (new file)
- `scripts/uninstall.sh` (new file)
- `tests/install_test.bats` (new file — exercises template rendering, NOT real `launchctl`)
- `Makefile` (replace the placeholder `install`/`uninstall` targets to call the real scripts)
- `CHANGELOG.md`

Off-limits:
- All `lib/` files.
- `scripts/check_memory_pressure.sh` (read-only).
- Top-level docs except `CHANGELOG.md` (README updates happen in task 08).

## Dependencies

`06-implement-entrypoint.md`.

## Implementation Notes

- Use the `set -Eeuo pipefail` + `trap ERR` boilerplate.
- Plist template placeholders:
  - `__LABEL__` → `com.dominic.memory-pressure-monitor`
  - `__PROGRAM__` → absolute path to `scripts/check_memory_pressure.sh`
  - `__WORKING_DIR__` → absolute path to repo root
  - `__INTERVAL__` → `MPM_INTERVAL_SECONDS`
  - `__STDOUT__` → `<MPM_LOG_DIR>/launchd.out.log`
  - `__STDERR__` → `<MPM_LOG_DIR>/launchd.err.log`
- `MPM_LOG_DIR` defaults to `$HOME/Library/Logs` (see `config/defaults.sh`).
- Required keys in the plist: `Label`, `ProgramArguments` (single entry, the absolute script path), `WorkingDirectory`, `StartInterval`, `RunAtLoad`, `StandardOutPath`, `StandardErrorPath`, `EnvironmentVariables` (passing through any user-supplied `MPM_*` overrides — read them from `~/.config/memory-pressure-monitor/config.sh` if it exists).
- Render template via `sed` substitution. Quote every replacement. Reject any value containing `]]>` or other XML-hostile content with a clear error.
- Render to `~/Library/LaunchAgents/com.dominic.memory-pressure-monitor.plist` (mode `0644`).
- Bootstrap with `launchctl bootstrap gui/$(id -u) <plist>`. If the label is already loaded, `launchctl bootout gui/$(id -u)/<label>` first **only when `--force` is passed**; otherwise refuse with a clear error.
- After bootstrap, run `launchctl print gui/$(id -u)/<label>` and grep for the label to verify the agent is loaded.
- `--dry-run` flag: render the plist, print it to stdout, and exit 0 without installing.
- `scripts/uninstall.sh`:
  - Boots out the label, removes the plist file.
  - Without `--purge`: leaves `state/last_alert.json` and the log files alone.
  - With `--purge`: removes both, with `rm -f` (never `rm -rf`).
  - Idempotent: running again exits 0 even if the agent is already gone.
- Test (`tests/install_test.bats`) does not call real `launchctl`. Instead, the test stubs `launchctl` on a temp `PATH` and asserts:
  - The rendered plist contains all expected absolute paths.
  - The rendered plist is valid XML (use `plutil -lint <plist>` if available; otherwise grep for required keys).
  - `--dry-run` does NOT touch `~/Library/LaunchAgents/`.
  - `install.sh` without `--force` refuses to clobber a pre-existing label (simulated via the stub).
  - `uninstall.sh --purge` calls `rm -f` on state and log paths (verified by stubbing `rm`).

## Acceptance Criteria

- [ ] `make fmt-check` passes
- [ ] `make lint` passes
- [ ] `bats tests/install_test.bats` covers all bullets above
- [ ] `make test` passes overall
- [ ] `scripts/install.sh --dry-run` prints a plausible plist on the user's machine
- [ ] `scripts/install.sh` then `scripts/uninstall.sh` runs end-to-end on the user's machine without manual cleanup
- [ ] Plist passes `plutil -lint`
- [ ] No `eval`, no unquoted expansions, no use of bash-4-only features
- [ ] Repo path containing spaces does NOT break install (verified by running install in a path under `/tmp/path with spaces/...` if practical)

## Documentation Requirement

- Add dated `CHANGELOG.md` entries:
  - `feat(launchd): plist template`
  - `feat(install): launchctl-based installer`
  - `feat(uninstall): bootout + optional purge`
- Update `REPO_STATUS.md` "Implemented features" once install + uninstall both work end-to-end.

## Commit Requirement

Commit each subcomponent independently when practical (template, installer, uninstaller). If the work is tightly coupled, one combined commit is acceptable; reflect that in the `CHANGELOG.md` group.
