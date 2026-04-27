# lib/state.sh — debounce state file manager.
#
# Sourced, never executed.
#
# Public API:
#   state::path                       -> prints the resolved state file path
#   state::should_alert <kind>        -> exit 0 if cooldown elapsed, 1 if not
#   state::record_alert <kind>        -> writes a fresh timestamp for <kind>
#   state::swap_active                -> exit 0 if swap was active on last tick
#   state::set_swap_active <true|false>
#   state::reset                      -> deletes the state file
#
# kind ∈ {red_pressure, swap_in_use}
# Cooldowns from MPM_RED_COOLDOWN_SECONDS / MPM_SWAP_COOLDOWN_SECONDS.
#
# State file format (schema=1):
#   {"schema":1,"last_alert":{"red_pressure":"<iso8601>|null","swap_in_use":"<iso8601>|null"},"swap_active":false}
#
# Honors:
#   MPM_STATE_PATH   — full path override
#   TEST_NOW         — epoch seconds for time math (tests)
#
# Depends on lib/log.sh (already sourced by caller).

# shellcheck shell=bash

_state::default_path() {
  local repo_root
  repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
  printf '%s/state/last_alert.json' "${repo_root}"
}

state::path() {
  printf '%s' "${MPM_STATE_PATH:-$(_state::default_path)}"
}

# _state::epoch_now: prints current epoch seconds (TEST_NOW override).
_state::epoch_now() {
  if [ -n "${TEST_NOW:-}" ]; then
    printf '%s' "${TEST_NOW}"
    return
  fi
  date '+%s'
}

# _state::iso_now: prints current ISO 8601 timestamp.
_state::iso_now() {
  if [ -n "${TEST_NOW_ISO:-}" ]; then
    printf '%s' "${TEST_NOW_ISO}"
    return
  fi
  date "+%Y-%m-%dT%H:%M:%S%z" | sed 's/\([+-][0-9][0-9]\)\([0-9][0-9]\)$/\1:\2/'
}

# _state::iso_to_epoch <iso8601>: prints epoch seconds for a stored ts.
# Strips the colon from the offset because BSD date -j -f only accepts +0700, not +07:00.
_state::iso_to_epoch() {
  local ts="$1"
  # Strip the colon in the offset, if present.
  ts="$(printf '%s' "${ts}" | sed 's/\([+-][0-9][0-9]\):\([0-9][0-9]\)$/\1\2/')"
  date -j -f "%Y-%m-%dT%H:%M:%S%z" "${ts}" '+%s' 2> /dev/null
}

# _state::cooldown_for <kind>: prints the configured cooldown in seconds.
_state::cooldown_for() {
  case "$1" in
    red_pressure) printf '%s' "${MPM_RED_COOLDOWN_SECONDS:-600}" ;;
    swap_in_use) printf '%s' "${MPM_SWAP_COOLDOWN_SECONDS:-900}" ;;
    *) return 2 ;;
  esac
}

# _state::extract <kind>: reads the state file and prints the stored ISO ts
# for <kind>, or empty if missing / null / corrupt.
#
# Matches "<kind>": "..." or "<kind>": null with optional JSON whitespace.
# Because kind values are a closed set ({red_pressure, swap_in_use}) and
# ISO 8601 timestamps cannot contain `"`, this is unambiguous without a
# real JSON parser.
_state::extract() {
  local kind="$1"
  local path
  path="$(state::path)"
  [ -f "${path}" ] || return 0
  local raw
  raw="$(cat "${path}" 2> /dev/null)" || return 0
  printf '%s' "${raw}" | tr '\n\r\t' '   ' | awk -v k="${kind}" '
    {
      pat = "\"" k "\"[[:space:]]*:[[:space:]]*(null|\"[^\"]*\")";
      if (!match($0, pat)) exit;
      rest = substr($0, RSTART, RLENGTH);
      sub(/^[^:]*:[[:space:]]*/, "", rest);
      if (rest == "null") exit;
      gsub(/^"|"$/, "", rest);
      print rest;
    }
  '
}

_state::has_key() {
  local key="$1" path raw
  path="$(state::path)"
  [ -f "${path}" ] || return 1
  raw="$(cat "${path}" 2> /dev/null)" || return 1
  printf '%s' "${raw}" | tr '\n\r\t' '   ' | awk -v k="${key}" '
    {
      pat = "\"" k "\"[[:space:]]*:";
      if (match($0, pat)) exit 0;
      exit 1;
    }
  '
}

# _state::extract_swap_active: prints true/false if present, else empty.
_state::extract_swap_active() {
  local path raw
  path="$(state::path)"
  [ -f "${path}" ] || return 0
  raw="$(cat "${path}" 2> /dev/null)" || return 0
  printf '%s' "${raw}" | awk '
    /"swap_active"[[:space:]]*:[[:space:]]*true/ { print "true"; exit }
    /"swap_active"[[:space:]]*:[[:space:]]*false/ { print "false"; exit }
  '
}

_state::current_swap_active_literal() {
  local active last_swap
  active="$(_state::extract_swap_active)"
  case "${active}" in
    true | false)
      printf '%s' "${active}"
      return
      ;;
  esac

  # Backward-compatible inference for v1 state files that predate
  # swap_active: a stored swap alert means the last known state was active.
  last_swap="$(_state::extract swap_in_use)"
  if [ -n "${last_swap}" ]; then
    printf 'true'
  else
    printf 'false'
  fi
}

# _state::write_atomic: writes both kinds (preserving the other when only
# one is being updated). Atomic via temp file + mv.
_state::write_atomic() {
  local red="$1" swap="$2" swap_active="$3"
  local path tmp dir target_existed
  path="$(state::path)"
  dir="$(dirname "${path}")"
  [ -d "${dir}" ] || mkdir -p "${dir}"

  if [ -L "${path}" ] || { [ -e "${path}" ] && [ ! -f "${path}" ]; }; then
    printf 'state target is not a regular file, refusing to write: %s\n' "${path}" >&2
    return 1
  fi
  if [ -e "${path}" ] && [ ! -O "${path}" ]; then
    printf 'state target is not owned by the current user, refusing to write: %s\n' "${path}" >&2
    return 1
  fi

  target_existed=0
  [ -e "${path}" ] && target_existed=1
  tmp="$(mktemp "${dir}/.last_alert.XXXXXX")"
  local red_field swap_field
  if [ -z "${red}" ]; then
    red_field='null'
  else
    red_field="\"${red}\""
  fi
  if [ -z "${swap}" ]; then
    swap_field='null'
  else
    swap_field="\"${swap}\""
  fi
  case "${swap_active}" in
    true | false) ;;
    *) swap_active='false' ;;
  esac

  printf '{"schema":1,"last_alert":{"red_pressure":%s,"swap_in_use":%s},"swap_active":%s}\n' \
    "${red_field}" "${swap_field}" "${swap_active}" > "${tmp}"
  mv -f "${tmp}" "${path}"
  if [ "${target_existed}" -eq 0 ]; then
    chmod 0644 "${path}" 2> /dev/null || true
  fi
}

state::should_alert() {
  local kind="$1"
  local cooldown
  cooldown="$(_state::cooldown_for "${kind}")" || return 2

  local path
  path="$(state::path)"
  if [ -f "${path}" ] && {
    ! grep -q '"schema"' "${path}" 2> /dev/null ||
      ! _state::has_key red_pressure ||
      ! _state::has_key swap_in_use
  }; then
    if command -v log::warn > /dev/null 2>&1; then
      log::warn state_corrupted reason=missing_schema kind="${kind}"
    fi
    return 0
  fi

  local last_iso last_epoch now_epoch
  last_iso="$(_state::extract "${kind}")"

  if [ -z "${last_iso}" ]; then
    return 0
  fi

  last_epoch="$(_state::iso_to_epoch "${last_iso}")"
  if [ -z "${last_epoch}" ]; then
    if command -v log::warn > /dev/null 2>&1; then
      log::warn state_corrupted reason=bad_timestamp kind="${kind}"
    fi
    return 0
  fi

  now_epoch="$(_state::epoch_now)"
  local elapsed
  elapsed=$((now_epoch - last_epoch))

  if [ "${elapsed}" -ge "${cooldown}" ]; then
    return 0
  fi
  return 1
}

state::record_alert() {
  local kind="$1"
  local now_iso
  now_iso="$(_state::iso_now)"

  local red swap swap_active
  red="$(_state::extract red_pressure)"
  swap="$(_state::extract swap_in_use)"
  swap_active="$(_state::current_swap_active_literal)"

  case "${kind}" in
    red_pressure) red="${now_iso}" ;;
    swap_in_use)
      swap="${now_iso}"
      swap_active='true'
      ;;
    *) return 2 ;;
  esac

  _state::write_atomic "${red}" "${swap}" "${swap_active}"
}

state::swap_active() {
  [ "$(_state::current_swap_active_literal)" = "true" ]
}

state::set_swap_active() {
  local desired="$1"
  case "${desired}" in
    true | false) ;;
    *) return 2 ;;
  esac

  local red swap
  red="$(_state::extract red_pressure)"
  swap="$(_state::extract swap_in_use)"
  _state::write_atomic "${red}" "${swap}" "${desired}"
}

state::reset() {
  local path
  path="$(state::path)"
  rm -f "${path}"
}
