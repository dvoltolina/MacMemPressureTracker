# lib/log.sh — JSONL logger.
#
# Sourced, never executed. Caller is responsible for `set -Eeuo pipefail`.
# All public API: log::info, log::warn, log::error, log::path.
#
# Each call appends one JSON object on its own line to MPM_LOG_PATH and,
# if MPM_LOG_TEE_STDERR=1, also writes the same line to stderr.
#
# Field order: ts, level, event, then any extra k=v pairs in argv order.
# Honors TEST_NOW for deterministic testing.

# shellcheck shell=bash

# _log::now: prints the current timestamp as ISO 8601 with colon-separated offset.
_log::now() {
  if [ -n "${TEST_NOW:-}" ]; then
    printf '%s' "${TEST_NOW}"
    return
  fi
  date "+%Y-%m-%dT%H:%M:%S%z" | sed 's/\([+-][0-9][0-9]\)\([0-9][0-9]\)$/\1:\2/'
}

# _log::escape_json: prints argv $1 with " and \ escaped for embedding in a
# JSON string. Also collapses control chars (\n, \r, \t) to escape sequences.
_log::escape_json() {
  local s="$1"
  s="${s//\\/\\\\}"
  s="${s//\"/\\\"}"
  # Tab -> \t, CR -> \r, LF -> \n. Use printf to materialize the literal chars
  # for matching since bash 3.2 has no $'\t' inside parameter expansion patterns
  # in all builds — but as RHS of ${var//pat/repl} it is fine.
  s="${s//$'\t'/\\t}"
  s="${s//$'\r'/\\r}"
  s="${s//$'\n'/\\n}"
  printf '%s' "${s}"
}

# _log::emit <level> <event> [k=v ...]
# Writes the JSON line to the configured log path (and optionally stderr).
_log::emit() {
  local level="$1"
  local event="$2"
  shift 2

  local ts
  ts="$(_log::now)"

  local out='{'
  out="${out}\"ts\":\"$(_log::escape_json "${ts}")\""
  out="${out},\"level\":\"$(_log::escape_json "${level}")\""
  out="${out},\"event\":\"$(_log::escape_json "${event}")\""

  local pair key val
  for pair in "$@"; do
    key="${pair%%=*}"
    val="${pair#*=}"
    # Numeric pass-through: integers and decimals emitted unquoted.
    case "${val}" in
      '' | *[!0-9.\-]*)
        out="${out},\"$(_log::escape_json "${key}")\":\"$(_log::escape_json "${val}")\""
        ;;
      *)
        out="${out},\"$(_log::escape_json "${key}")\":${val}"
        ;;
    esac
  done
  out="${out}}"

  local log_path="${MPM_LOG_PATH:-${HOME}/Library/Logs/memory-pressure-monitor.log}"
  local log_dir
  log_dir="$(dirname "${log_path}")"
  if [ ! -d "${log_dir}" ]; then
    mkdir -p "${log_dir}" 2> /dev/null || true
  fi

  if [ -L "${log_path}" ]; then
    printf 'log target is a symlink, refusing to write: %s\n' "${log_path}" >&2
    return 0
  fi

  if [ ! -e "${log_path}" ]; then
    : > "${log_path}" 2> /dev/null || true
    chmod 0644 "${log_path}" 2> /dev/null || true
  fi

  printf '%s\n' "${out}" >> "${log_path}" 2> /dev/null || true
  chmod 0644 "${log_path}" 2> /dev/null || true

  if [ "${MPM_LOG_TEE_STDERR:-0}" = "1" ]; then
    printf '%s\n' "${out}" >&2
  fi
}

log::info() { _log::emit "info" "$@"; }
log::warn() { _log::emit "warn" "$@"; }
log::error() { _log::emit "error" "$@"; }

# log::path: prints the resolved log path to stdout.
log::path() {
  printf '%s\n' "${MPM_LOG_PATH:-${HOME}/Library/Logs/memory-pressure-monitor.log}"
}
