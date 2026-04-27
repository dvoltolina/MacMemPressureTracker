# lib/config.sh — safe configuration loader.
#
# Sourced, never executed.
#
# Public API:
#   config::load [config_path]  -> load defaults, then a strict user override file
#   config::validate            -> validate loaded MPM_* values
#
# User config intentionally is not sourced as shell. It accepts only
# whitelisted KEY=value lines, optional single/double quotes around values,
# blank lines, and comments.

# shellcheck shell=bash

_config::repo_root() {
  cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd
}

_config::user_path() {
  printf '%s' "${MPM_CONFIG_PATH:-${HOME}/.config/memory-pressure-monitor/config.sh}"
}

_config::trim() {
  sed 's/^[[:space:]]*//;s/[[:space:]]*$//'
}

_config::allowed_key() {
  case "$1" in
    MPM_INTERVAL_SECONDS | \
      MPM_RED_COOLDOWN_SECONDS | \
      MPM_SWAP_COOLDOWN_SECONDS | \
      MPM_SWAP_THRESHOLD_MIB | \
      MPM_NOTIFICATION_BACKEND | \
      MPM_NOTIFICATION_SOUND | \
      MPM_LOG_PATH | \
      MPM_STATE_PATH | \
      MPM_LOG_TEE_STDERR)
      return 0
      ;;
    *)
      return 1
      ;;
  esac
}

_config::fail() {
  printf 'config error: %s\n' "$*" >&2
}

_config::parse_line() {
  local line="$1" key val
  line="$(printf '%s' "${line}" | _config::trim)"

  case "${line}" in
    '' | \#*) return 0 ;;
  esac

  case "${line}" in
    *=*) ;;
    *)
      _config::fail "expected KEY=value, got: ${line}"
      return 1
      ;;
  esac

  key="$(printf '%s' "${line%%=*}" | _config::trim)"
  val="$(printf '%s' "${line#*=}" | _config::trim)"

  if ! _config::allowed_key "${key}"; then
    _config::fail "unsupported key: ${key}"
    return 1
  fi

  case "${val}" in
    \"*\")
      val="${val#\"}"
      val="${val%\"}"
      ;;
    \'*\')
      val="${val#\'}"
      val="${val%\'}"
      ;;
    \"* | \'*)
      _config::fail "unterminated quoted value for ${key}"
      return 1
      ;;
    *)
      val="$(printf '%s' "${val}" | sed 's/[[:space:]]#.*$//;s/[[:space:]]*$//')"
      ;;
  esac

  export "${key}=${val}"
}

_config::load_user_file() {
  local path="$1" line
  [ -f "${path}" ] || return 0
  while IFS= read -r line || [ -n "${line}" ]; do
    _config::parse_line "${line}" || return 1
  done < "${path}"
}

_config::is_uint() {
  case "$1" in
    '' | *[!0-9]*) return 1 ;;
    *) return 0 ;;
  esac
}

_config::require_uint() {
  local key="$1" val="$2"
  if ! _config::is_uint "${val}"; then
    _config::fail "${key} must be an unsigned integer, got: ${val}"
    return 1
  fi
}

_config::require_positive_uint() {
  local key="$1" val="$2"
  _config::require_uint "${key}" "${val}" || return 1
  if [ "${val}" -eq 0 ]; then
    _config::fail "${key} must be greater than zero"
    return 1
  fi
}

_config::require_absolute_path() {
  local key="$1" val="$2"
  case "${val}" in
    /*) return 0 ;;
    *)
      _config::fail "${key} must be an absolute path, got: ${val}"
      return 1
      ;;
  esac
}

config::validate() {
  _config::require_positive_uint MPM_INTERVAL_SECONDS "${MPM_INTERVAL_SECONDS:-}" || return 1
  _config::require_uint MPM_RED_COOLDOWN_SECONDS "${MPM_RED_COOLDOWN_SECONDS:-}" || return 1
  _config::require_uint MPM_SWAP_COOLDOWN_SECONDS "${MPM_SWAP_COOLDOWN_SECONDS:-}" || return 1
  _config::require_uint MPM_SWAP_THRESHOLD_MIB "${MPM_SWAP_THRESHOLD_MIB:-}" || return 1

  case "${MPM_NOTIFICATION_BACKEND:-}" in
    osascript | terminal-notifier | stderr) ;;
    *)
      _config::fail "MPM_NOTIFICATION_BACKEND must be osascript, terminal-notifier, or stderr"
      return 1
      ;;
  esac

  case "${MPM_LOG_TEE_STDERR:-0}" in
    0 | 1) ;;
    *)
      _config::fail "MPM_LOG_TEE_STDERR must be 0 or 1"
      return 1
      ;;
  esac

  _config::require_absolute_path MPM_LOG_PATH "${MPM_LOG_PATH:-}" || return 1
  if [ -n "${MPM_STATE_PATH:-}" ]; then
    _config::require_absolute_path MPM_STATE_PATH "${MPM_STATE_PATH}" || return 1
  fi
}

config::load() {
  local repo_root config_path
  repo_root="$(_config::repo_root)"
  config_path="${1:-$(_config::user_path)}"

  # shellcheck source=/dev/null
  . "${repo_root}/config/defaults.sh"

  _config::load_user_file "${config_path}" || return 1
  config::validate
}
