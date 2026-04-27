# App Dashboard Breakdown

## Feature Areas Affected

- Runtime status reporting for the existing launchd monitor.
- A small native macOS dashboard app that wraps existing scripts.
- App icon generation and app bundle build tooling.
- Public README, changelog, and status documentation.

## Files Likely To Change

- `scripts/status.sh`
- `scripts/build-app.sh`
- `app/MemoryPressureMonitor/AppDelegate.swift`
- `app/MemoryPressureMonitor/Info.plist.tmpl`
- `app/MemoryPressureMonitor/IconFactory.swift`
- `README.md`
- `CHANGELOG.md`
- `Makefile`
- Focused tests under `tests/`

## Data Model Changes

None. The dashboard reads existing launchd state, `state/last_alert.json`, and JSONL logs. It does not
introduce a database or mutate monitor state beyond invoking existing install/uninstall scripts.

## API / Backend / Service Changes

None. The dashboard is local-only and invokes existing scripts. `scripts/status.sh` is a new local
CLI API for human and app status.

## Security / Permissions / Policy Changes

- No elevation. The app and scripts must refuse root/sudo behavior consistently.
- The app may run only repo-local scripts with fixed arguments.
- No network, telemetry, or external URLs.

## Storage Or File-Handling Changes

- Build artifacts live under `build/` and remain ignored.
- App icon source lives under `app/MemoryPressureMonitor/`.
- Generated icon assets are recreated by `scripts/build-app.sh`.

## Backward Compatibility

The existing launchd install, uninstall, notification, state, and log flows must keep working.

## Migration Concerns

None.

## User-Facing Edge Cases

- Agent installed but not loaded.
- Agent loaded but no app log exists yet.
- Invalid user config.
- Notification permission not granted.
- Repo path contains spaces.

## Testing Strategy

- Syntax-check all shell scripts.
- Compile the Swift dashboard app.
- Run `scripts/status.sh` in human and JSON modes.
- Validate rendered app `Info.plist`.
- Run `./scripts/install.sh --dry-run`.
- Run `make check` only if local dev tools are installed.

## Manual QA Checklist

- Build the app and open the `.app`.
- Confirm dashboard shows loaded/installed/log status.
- Click Refresh.
- Click Install / Reload.
- Click Test Notification and approve macOS permission if prompted.
- Click Open Log.
- Verify existing CLI install/uninstall still works.

## Known Non-Goals

- No menu bar agent.
- No background daemon beyond the existing launchd job.
- No live charts or real-time sampling UI.
- No Swift Package Manager or Xcode project unless needed later.
