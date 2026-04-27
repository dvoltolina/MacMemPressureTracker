# Memory Pressure Monitor

A small macOS background utility that sends a notification when memory pressure becomes
critical or the system starts using swap.

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
MPM_LOG_PATH="$HOME/Library/Logs/memory-pressure-monitor.log"
```

Run `./scripts/install.sh --force` after changing configuration.

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
