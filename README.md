# Memory Pressure Monitor

A small macOS background utility that sends a notification when memory pressure becomes
critical or swap is first observed in use. After swap clears, a later return to swap usage
can notify again.

It runs as a user-level `launchd` agent. There is no GUI, server, telemetry, or third-party
runtime dependency.

## Requirements

- macOS with `launchd`
- Bash 3.2 or newer, which is included with macOS
- Notification permission for the process that posts alerts, usually Script Editor via
  `osascript`

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

Example:

```sh
MPM_INTERVAL_SECONDS=30
MPM_RED_COOLDOWN_SECONDS=600
MPM_SWAP_COOLDOWN_SECONDS=900
MPM_SWAP_THRESHOLD_MIB=64
MPM_NOTIFICATION_BACKEND=osascript
MPM_NOTIFICATION_SOUND=
MPM_LOG_PATH=/Users/dominic/Library/Logs/memory-pressure-monitor.log
```

The override file is parsed as strict `KEY=value` data, not executed as shell. Use absolute
paths; shell expansion like `$HOME` and `~` is intentionally not supported in this file.

Most settings are loaded on the next tick. Run `./scripts/install.sh --force` after changing
`MPM_INTERVAL_SECONDS`, because that value is rendered into the launchd plist.

## Notification Permission

The first notification may trigger a macOS permission prompt for Script Editor or
`osascript`. Approve it to receive future alerts.

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
