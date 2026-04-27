# INDEX — memory-monitor-mvp

## Summary

Ship the minimum viable end-to-end loop: `launchd` → sampler → debounce → notification. After this pack lands, the user can install the agent and receive notifications when memory pressure goes red or swap is in use.

See [`BREAKDOWN.md`](BREAKDOWN.md) for the risk-and-architecture breakdown that motivated this pack.

## Tasks

| File | Summary | Complexity | Depends on | Target files | Verification | Parallel-safe |
| --- | --- | --- | --- | --- | --- | --- |
| `01-capture-fixtures.md` | Capture real `memory_pressure`, `vm_stat`, `sysctl vm.swapusage` output as test fixtures | Small | None | `tests/fixtures/*.txt` | manual | Yes (no overlap) |
| `02-implement-log-lib.md` | `lib/log.sh` JSONL logger with level helpers | Small | None | `lib/log.sh`, `tests/log_test.bats` | `make check` | Yes (no overlap) |
| `03-implement-pressure-lib.md` | `lib/pressure.sh` parser for memory and swap metrics | Medium | `01-capture-fixtures.md` | `lib/pressure.sh`, `tests/pressure_test.bats` | `make check` | Yes (different file from 02 / 04) |
| `04-implement-state-lib.md` | `lib/state.sh` debounce + state file read/write | Medium | `02-implement-log-lib.md` | `lib/state.sh`, `tests/state_test.bats` | `make check` | Yes (different file from 03) |
| `05-implement-notify-lib.md` | `lib/notify.sh` osascript notification driver | Small | `02-implement-log-lib.md` | `lib/notify.sh`, `tests/notify_test.bats` | `make check` | Yes (different file from 03 / 04) |
| `06-implement-entrypoint.md` | `scripts/check_memory_pressure.sh` wiring sampler → state → notify | Medium | 02, 03, 04, 05 | `scripts/check_memory_pressure.sh`, `tests/check_memory_pressure_test.bats` | `make check` | No (depends on all libs) |
| `07-launchd-template-and-installer.md` | `launchd/*.plist.tmpl`, `scripts/install.sh`, `scripts/uninstall.sh` | Medium | `06-implement-entrypoint.md` | `launchd/com.dominic.memory-pressure-monitor.plist.tmpl`, `scripts/install.sh`, `scripts/uninstall.sh`, `tests/install_test.bats` | `make check` + manual install/uninstall | No |
| `08-update-readme-and-status.md` | Replace placeholder install instructions in `README.md`; mark feature done in `REPO_STATUS.md` | Small | `07-launchd-template-and-installer.md` | `README.md`, `REPO_STATUS.md` | manual | No (touches docs others will not) |

## Recommended execution order

```
01 ──┐
02 ──┼─► 03 ──┐
     ├─► 04 ──┤
     └─► 05 ──┤
              ▼
              06 ──► 07 ──► 08
```

1. Run **01** and **02** in parallel — no shared files.
2. Once **01** and **02** complete: run **03**, **04**, **05** in parallel — each writes a different `lib/*.sh` and `tests/*_test.bats`.
3. Run **06** after all libraries exist.
4. Run **07** after the entrypoint is in place.
5. Run **08** last to update top-level docs.

## Parallelism

- May run in parallel: `(01, 02)`, then `(03, 04, 05)`.
- Must run serially: `06` after `02–05`; `07` after `06`; `08` after `07`.

## Known risks

- **Fixture drift across macOS versions.** Mitigation: filename-encode the macOS version (e.g. `vm_stat_macos14.txt`) and have `lib/pressure.sh` accept multiple format variants.
- **Notification permission gate.** First run will show a system prompt; user must approve. Mitigation: `README.md` calls this out before install.
- **launchd label collision.** Mitigation: installer checks for an existing label and refuses to clobber unless `--force`.
- **Repo path contains spaces.** Mitigation: every script and the plist template use absolute, fully-quoted paths. Tests cover a path-with-spaces scenario.
- **`shellcheck` is strict.** Mitigation: every PR runs `make lint` locally before commit; CI is only a backstop.

## Final verification checklist

- [ ] `make fmt-check` passes
- [ ] `make lint` passes
- [ ] `make test` passes
- [ ] Install on real device: `./scripts/install.sh` exits 0
- [ ] `launchctl print gui/$UID/com.dominic.memory-pressure-monitor` shows the agent loaded
- [ ] Synthetic red-pressure event produces one notification within `MPM_INTERVAL_SECONDS + a few seconds`
- [ ] Second simulated event within cooldown produces NO notification
- [ ] Uninstall: `./scripts/uninstall.sh` exits 0; agent no longer listed
- [ ] `--purge` flag removes state and log; default uninstall preserves state
- [ ] `REPO_STATUS.md` updated to mark feature implemented
- [ ] `CHANGELOG.md` has a dated `### Feature: memory-monitor-mvp` group with entries per task
