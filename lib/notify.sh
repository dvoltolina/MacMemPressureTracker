# lib/notify.sh — notification driver.
#
# Sourced, never executed.
#
# Public API:
#   notify::send <title> <body> [sound] [kind] [extra-args...]
#
# Backends (selected via MPM_NOTIFICATION_BACKEND):
#   popup              (default) — centered window via the dashboard app
#   osascript                    — macOS native AppleScript banner
#   terminal-notifier  (opt-in)  — falls back to osascript if not on PATH
#   stderr             (test)    — prints a deterministic line to stderr
#
# Title and body are passed to AppleScript / the helper as argv, never
# interpolated into AppleScript source.
#
# Depends on lib/log.sh.

# shellcheck shell=bash

# _notify::escape_argv: prints argv[1] as a deterministic literal — used for
# stderr backend output. Just trim line breaks.
_notify::escape_argv() {
  local s="$1"
  s="${s//$'\n'/\\n}"
  s="${s//$'\r'/\\r}"
  printf '%s' "${s}"
}

_notify::backend_stderr() {
  local title="$1" body="$2" sound="${3:-}"
  shift 3 2> /dev/null || shift $#
  local kind="${1:-}"
  local extras="$*"
  printf 'notify: title=%s body=%s sound=%s kind=%s extras=%s\n' \
    "$(_notify::escape_argv "${title}")" \
    "$(_notify::escape_argv "${body}")" \
    "$(_notify::escape_argv "${sound}")" \
    "$(_notify::escape_argv "${kind}")" \
    "$(_notify::escape_argv "${extras}")" >&2
}

_notify::backend_osascript() {
  local title="$1" body="$2" sound="${3:-}"
  if [ -n "${sound}" ]; then
    osascript \
      -e 'on run argv' \
      -e 'display notification (item 2 of argv) with title (item 1 of argv) sound name (item 3 of argv)' \
      -e 'end run' \
      "${title}" "${body}" "${sound}"
  else
    osascript \
      -e 'on run argv' \
      -e 'display notification (item 2 of argv) with title (item 1 of argv)' \
      -e 'end run' \
      "${title}" "${body}"
  fi
}

_notify::backend_terminal_notifier() {
  local title="$1" body="$2" sound="${3:-}"
  if ! command -v terminal-notifier > /dev/null 2>&1; then
    if command -v log::warn > /dev/null 2>&1; then
      log::warn notify_fallback reason=terminal_notifier_missing
    fi
    _notify::backend_osascript "${title}" "${body}" "${sound}"
    return $?
  fi
  if [ -n "${sound}" ]; then
    terminal-notifier -title "${title}" -message "${body}" -sound "${sound}"
  else
    terminal-notifier -title "${title}" -message "${body}"
  fi
}

_notify::popup_app_binary() {
  local repo_root
  repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
  printf '%s/build/Memory Pressure Monitor.app/Contents/MacOS/Memory Pressure Monitor' "${repo_root}"
}

_notify::popup_already_visible() {
  # Match against the full path of the popup binary plus the --alert flag.
  # Tightened from the original `Memory Pressure Monitor.*--alert` pattern,
  # which could be matched by an unrelated user process whose cmdline
  # coincidentally contained both substrings — a denial-of-alert risk
  # since the visible-popup check would suppress legitimate alerts.
  local binary
  binary="$(_notify::popup_app_binary)"
  pgrep -f "${binary}.*--alert" > /dev/null 2>&1
}

# Argv contract for the dashboard binary's --alert mode:
#   --alert <kind> --title <text> --body <text>
#   [--zone <z>] [--free-pct <n>] [--swap-mib <n>] [--allow-quit]
#
# --allow-quit is appended only when MPM_POPUP_ALLOW_QUIT=1. It enables
# per-row Quit buttons in the popup that send SIGTERM to the selected
# process (subject to the hardcoded never-kill list inside the binary).
_notify::backend_popup() {
  local title="$1" body="$2" sound="${3:-}"
  shift 3 2> /dev/null || shift $#
  local kind="${1:-info}"
  shift 2> /dev/null || true

  local binary
  binary="$(_notify::popup_app_binary)"
  if [ ! -x "${binary}" ]; then
    if command -v log::warn > /dev/null 2>&1; then
      log::warn notify_fallback reason=app_missing path="${binary}"
    fi
    _notify::backend_osascript "${title}" "${body}" "${sound}"
    return $?
  fi

  # If a popup from a prior tick is still on screen, do not stack a second
  # one. The cooldown that follows this call still starts as if the alert
  # was delivered — that is intentional. The visible popup already conveys
  # the situation; another one only adds noise.
  if _notify::popup_already_visible; then
    if command -v log::info > /dev/null 2>&1; then
      log::info notify_skip reason=popup_already_visible kind="${kind}"
    fi
    return 0
  fi

  # Branch the nohup invocation rather than using a conditionally-empty
  # array: bash 3.2 (the macOS system shell) errors on "${arr[@]}" under
  # `set -u` when the array is empty, and the ${arr[@]+"${arr[@]}"}
  # workaround is harder to read than two explicit calls.
  if [ "${MPM_POPUP_ALLOW_QUIT:-0}" = "1" ]; then
    nohup "${binary}" \
      --alert "${kind}" \
      --title "${title}" \
      --body "${body}" \
      "$@" \
      --allow-quit > /dev/null 2>&1 &
  else
    nohup "${binary}" \
      --alert "${kind}" \
      --title "${title}" \
      --body "${body}" \
      "$@" > /dev/null 2>&1 &
  fi
  disown 2> /dev/null || true
  return 0
}

notify::send() {
  local title="$1" body="$2" sound="${3:-${MPM_NOTIFICATION_SOUND:-}}"
  shift 3 2> /dev/null || shift $#
  local kind="${1:-info}"
  shift 2> /dev/null || true
  local backend="${MPM_NOTIFICATION_BACKEND:-popup}"
  local rc=0

  case "${backend}" in
    popup) _notify::backend_popup "${title}" "${body}" "${sound}" "${kind}" "$@" || rc=$? ;;
    stderr) _notify::backend_stderr "${title}" "${body}" "${sound}" "${kind}" "$@" || rc=$? ;;
    terminal-notifier) _notify::backend_terminal_notifier "${title}" "${body}" "${sound}" || rc=$? ;;
    osascript | *) _notify::backend_osascript "${title}" "${body}" "${sound}" || rc=$? ;;
  esac

  if command -v log::info > /dev/null 2>&1; then
    if [ "${rc}" -eq 0 ]; then
      log::info notify_attempt backend="${backend}" rc=0 kind="${kind}"
    else
      log::warn notify_failed backend="${backend}" rc="${rc}" kind="${kind}"
    fi
  fi

  return "${rc}"
}
