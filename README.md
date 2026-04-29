# Memory Pressure Monitor

A small macOS background utility that sends a notification when memory pressure rises into
the warn or critical zone, or when swap usage grows past the last-alerted level. By default
alerts are shown as a centered popup window listing the top processes by memory; the popup
points at Activity Monitor for follow-up. The classic macOS banner (`osascript`) remains
available behind a config switch.

It runs as a user-level `launchd` agent. The background monitor has no always-running GUI,
server, telemetry, or third-party runtime dependency. An optional dashboard app can be built
from this repo for status and basic controls.

## Requirements

- macOS with `launchd`
- Bash 3.2 or newer, which is included with macOS
- Notification permission for the process that posts alerts, usually Script Editor via
  `osascript`

The optional dashboard build also requires Xcode Command Line Tools for `/usr/bin/swiftc`,
`/usr/bin/iconutil`, and `plutil`:

```sh
xcode-select --install
```

## Install

Clone the repository, then run:

```sh
./scripts/install.sh
```

Do not use `sudo`; the monitor is a per-user launchd agent.

To preview the generated launchd plist without installing it:

```sh
./scripts/install.sh --dry-run
```

To reload after changing configuration:

```sh
./scripts/install.sh --force
```

## Check Status

To see whether the background monitor is installed and currently loaded by `launchd`:

```sh
./scripts/status.sh
```

For machine-readable output:

```sh
./scripts/status.sh --json
```

`Status: Running` means the agent is loaded and has written at least one sample log.
`Launchd loaded: yes` without a recent sample means launchd has the job loaded, but the
dashboard cannot yet prove that sampling is healthy. `Plist installed: yes` but
`Launchd loaded: no` means the launchd file exists but the job is not currently loaded.

## Dashboard App

Build the small native dashboard app:

```sh
make app
```

Then open:

```sh
open "build/Memory Pressure Monitor.app"
```

The dashboard shows the same running status as `scripts/status.sh` and provides buttons to
refresh status, install/reload the launchd job, uninstall it, send a test notification, and
reveal the log file in Finder.

The app bundle stores the current repository path at build time. If you move the repository,
run `make app` again and reinstall the launchd job from the new path.

Do not run the dashboard with `sudo`; it is a per-user app for a per-user launchd agent.
The Test Notification button can confirm that the notification command ran, but macOS does
not provide a reliable delivery confirmation. If no banner appears, check notification
settings for Script Editor or `osascript`.

## Uninstall

```sh
./scripts/uninstall.sh
```

To also remove local state and logs:

```sh
./scripts/uninstall.sh --purge
```

`--purge` removes only the default app-owned state and log files. If you configured custom
state or log paths, remove those manually after checking the path.

## Configuration

Defaults live in `config/defaults.sh`. To override them, create:

```sh
~/.config/memory-pressure-monitor/config.sh
```

All keys, with their defaults:

| Key | Default | Effect |
| --- | --- | --- |
| `MPM_INTERVAL_SECONDS` | `30` | How often launchd invokes the sampler. Rendered into the plist; needs `install.sh --force` to take effect. |
| `MPM_RED_COOLDOWN_SECONDS` | `600` | Cooldown before another red-zone alert. |
| `MPM_WARN_ALERTS_ENABLED` | `1` | Set to `0` to silence warn-zone alerts entirely. |
| `MPM_WARN_COOLDOWN_SECONDS` | `1800` | Cooldown before another warn-zone alert. |
| `MPM_SWAP_COOLDOWN_SECONDS` | `900` | Cooldown before another swap alert. |
| `MPM_SWAP_THRESHOLD_MIB` | `64` | Swap level at or above which swap is considered "in use". |
| `MPM_SWAP_GROWTH_MIB` | `1024` | Re-fire a swap alert once swap grows this many MiB above the last-alerted level. |
| `MPM_NOTIFICATION_BACKEND` | `popup` | `popup` (centered window, default), `osascript` (banner), `terminal-notifier`, or `stderr` (test). |
| `MPM_NOTIFICATION_SOUND` | _(empty)_ | Optional system sound name for the banner backends. |
| `MPM_LOG_PATH` | `~/Library/Logs/memory-pressure-monitor.log` | App log path. |

The override file is parsed as strict `KEY=value` data, not executed as shell. Use absolute
paths; shell expansion like `$HOME` and `~` is intentionally not supported in this file.

Most settings are loaded on the next tick. Run `./scripts/install.sh --force` after changing
`MPM_INTERVAL_SECONDS`, because that value is rendered into the launchd plist.

### Notification Backend

`popup` (default) launches the dashboard binary in alert mode and shows a centered window
that lists the top 8 processes by RSS, with an "Open Activity Monitor" button. The popup
auto-dismisses after 90 seconds. The popup binary is the same `Memory Pressure Monitor.app`
built by `make app`; if the app bundle is missing, the sampler falls back to `osascript`
and logs `notify_fallback reason=app_missing`.

To switch back to the classic macOS banner:

```sh
MPM_NOTIFICATION_BACKEND=osascript
```

## Notification Permission

The first time the banner backend fires, macOS may prompt for permission for Script Editor
or `osascript`. Approve it to receive future banner alerts. The popup backend does not need
notification permission since it is a regular app window.

To trigger that prompt proactively:

```sh
osascript -e 'display notification "Notifications are enabled." with title "Memory Pressure Monitor test"'
```

The monitor records notification attempts even if macOS blocks delivery, so a denied prompt
will still start the cooldown. After granting permission, wait for the cooldown to expire or
remove `state/last_alert.json` to test immediately.

## Login Behavior

The launchd agent has `RunAtLoad` and `StartInterval`, so it starts again at login as long as
this repository stays at the same path. If you move the repo, run `./scripts/install.sh --force`
from the new location.

## Logs

The default application log is:

```sh
~/Library/Logs/memory-pressure-monitor.log
```

The launchd stdout and stderr logs are:

```sh
~/Library/Logs/memory-pressure-monitor.launchd.out.log
~/Library/Logs/memory-pressure-monitor.launchd.err.log
```

## Development

Optional development tools:

- `bats-core` for tests
- `shellcheck` for linting
- `shfmt` for formatting

Install them with Homebrew:

```sh
make dev-deps
```

Run checks:

```sh
make check
```

## Privacy

The utility runs locally and does not make network requests. It samples macOS memory pressure
and swap usage, writes local logs, and sends local notifications.

## License

MIT. See [LICENSE](LICENSE).
