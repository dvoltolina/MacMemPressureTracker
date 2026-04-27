# lib/notify.sh — notification driver.
#
# Sourced, never executed.
#
# Public API:
#   notify::send <title> <body> [sound]
#
# Backends (selected via MPM_NOTIFICATION_BACKEND):
#   osascript          (default) — macOS native AppleScript notification
#   terminal-notifier  (opt-in)  — falls back to osascript if not on PATH
#   stderr             (test)    — prints a deterministic line to stderr
#
# Title and body are escaped before being embedded in AppleScript.
#
# Depends on lib/log.sh.

# shellcheck shell=bash

# _notify::escape_applescript: doubles every backslash and double-quote so
# the value can be safely embedded inside an AppleScript double-quoted string.
_notify::escape_applescript() {
  local s="$1"
  s="${s//\\/\\\\}"
  s="${s//\"/\\\"}"
  printf '%s' "${s}"
}

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
  printf 'notify: title=%s body=%s sound=%s\n' \
    "$(_notify::escape_argv "${title}")" \
    "$(_notify::escape_argv "${body}")" \
    "$(_notify::escape_argv "${sound}")" >&2
}

_notify::backend_osascript() {
  local title="$1" body="$2" sound="${3:-}"
  local et eb es script
  et="$(_notify::escape_applescript "${title}")"
  eb="$(_notify::escape_applescript "${body}")"
  if [ -n "${sound}" ]; then
    es="$(_notify::escape_applescript "${sound}")"
    script="display notification \"${eb}\" with title \"${et}\" sound name \"${es}\""
  else
    script="display notification \"${eb}\" with title \"${et}\""
  fi
  osascript -e "${script}"
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

notify::send() {
  local title="$1" body="$2" sound="${3:-${MPM_NOTIFICATION_SOUND:-}}"
  local backend="${MPM_NOTIFICATION_BACKEND:-osascript}"
  local rc=0

  case "${backend}" in
    stderr) _notify::backend_stderr "${title}" "${body}" "${sound}" || rc=$? ;;
    terminal-notifier) _notify::backend_terminal_notifier "${title}" "${body}" "${sound}" || rc=$? ;;
    osascript | *) _notify::backend_osascript "${title}" "${body}" "${sound}" || rc=$? ;;
  esac

  if command -v log::info > /dev/null 2>&1; then
    if [ "${rc}" -eq 0 ]; then
      log::info notify_attempt backend="${backend}" rc=0
    else
      log::warn notify_failed backend="${backend}" rc="${rc}"
    fi
  fi

  return "${rc}"
}
