# App Dashboard Prompt Pack

## Task Table

| Prompt filename | Summary | Complexity | Dependencies | Target files | Verification commands | Parallel safe |
| --- | --- | --- | --- | --- | --- | --- |
| `01-status-helper.md` | Add a CLI status helper for launchd/log/state visibility | Small | None | `scripts/status.sh`, `tests/status_test.bats`, `Makefile`, `CHANGELOG.md` | `bash -n scripts/status.sh`; `scripts/status.sh`; `scripts/status.sh --json` | Yes |
| `02-native-dashboard-app.md` | Add native AppKit dashboard app, app icon generator, and build script | Medium | `01-status-helper.md` | `app/MemoryPressureMonitor/*`, `scripts/build-app.sh`, `tests/app_build_test.bats`, `Makefile`, `README.md`, `CHANGELOG.md` | `bash -n scripts/build-app.sh`; `./scripts/build-app.sh`; `plutil -lint build/Memory Pressure Monitor.app/Contents/Info.plist` | No |
| `03-docs-and-verification.md` | Update user docs and final verification notes | Small | `01-status-helper.md`, `02-native-dashboard-app.md` | `README.md`, `CHANGELOG.md`, `REPO_STATUS.md` | `git diff --check`; strongest available local verification | No |

## Recommended Execution Order

1. `01-status-helper.md`
2. `02-native-dashboard-app.md`
3. `03-docs-and-verification.md`

## Parallel Execution

Only `01-status-helper.md` is independent. The dashboard depends on the status helper because the
app should call the same status surface users can run from Terminal.

## Serial Requirements

`02-native-dashboard-app.md` and `03-docs-and-verification.md` must run serially because they both
touch user-facing docs and the final verification summary.

## Known Risks

- Local dev tools (`bats`, `shellcheck`, `shfmt`) may not be installed.
- Building a native `.app` depends on `/usr/bin/swiftc` and `/usr/bin/iconutil`.
- The app bundle is path-bound to the repo root, matching the existing launchd install behavior.
- macOS notification permission must still be granted manually.

## Final Verification Checklist

- [ ] `bash -n scripts/*.sh lib/*.sh`
- [ ] `scripts/status.sh` human output works.
- [ ] `scripts/status.sh --json` emits parseable JSON.
- [ ] `./scripts/build-app.sh` creates `build/Memory Pressure Monitor.app`.
- [ ] App `Info.plist` passes `plutil -lint`.
- [ ] `./scripts/install.sh --dry-run` still passes.
- [ ] `make check` run or documented as unavailable.
- [ ] Audit agents launched and findings classified.
