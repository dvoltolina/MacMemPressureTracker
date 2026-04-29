# lib/state.sh — debounce state file manager.
#
# Sourced, never executed.
#
# Public API:
#   state::path                                      -> resolved state file path
#   state::should_alert <kind>                       -> exit 0 if cooldown elapsed
#   state::record_alert <kind> [<swap_used_mib>]     -> writes a fresh timestamp
#   state::swap_alerted_mib                          -> prints the swap level (MiB)
#                                                       at which the last
#                                                       swap_in_use alert fired
#                                                       (0 if never)
#   state::set_swap_alerted_mib <int>                -> overwrites the swap
#                                                       high-water field
#   state::reset                                     -> deletes the state file
#
# kind ∈ {red_pressure, warn_pressure, swap_in_use}
# Cooldowns from MPM_RED_COOLDOWN_SECONDS / MPM_WARN_COOLDOWN_SECONDS /
# MPM_SWAP_COOLDOWN_SECONDS.
#
# State file format (schema=2):
#   {"schema":2,
#    "last_alert":{"red_pressure":"<iso>|null",
#                  "warn_pressure":"<iso>|null",
#                  "swap_in_use":"<iso>|null"},
#    "swap_alerted_mib":<int>}
#
# Schema 1 (legacy) is read transparently: a swap_active=true v1 file is
# treated as swap_alerted_mib=MPM_SWAP_THRESHOLD_MIB so the new growth
# decision starts from a sensible baseline. The next write rewrites the
# file as schema 2.
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
  ts="$(printf '%s' "${ts}" | sed 's/\([+-][0-9][0-9]\):\([0-9][0-9]\)$/\1\2/')"
  date -j -f "%Y-%m-%dT%H:%M:%S%z" "${ts}" '+%s' 2> /dev/null
}

# _state::cooldown_for <kind>: prints the configured cooldown in seconds.
_state::cooldown_for() {
  case "$1" in
    red_pressure) printf '%s' "${MPM_RED_COOLDOWN_SECONDS:-600}" ;;
    warn_pressure) printf '%s' "${MPM_WARN_COOLDOWN_SECONDS:-1800}" ;;
    swap_in_use) printf '%s' "${MPM_SWAP_COOLDOWN_SECONDS:-900}" ;;
    *) return 2 ;;
  esac
}

# _state::raw: prints the raw state file contents, or empty if missing.
_state::raw() {
  local path
  path="$(state::path)"
  [ -f "${path}" ] || return 0
  cat "${path}" 2> /dev/null || return 0
}

# _state::extract <kind>: prints the stored ISO timestamp for <kind> or empty.
# kind values are a closed set and ISO 8601 timestamps cannot contain ", so
# regex matching is unambiguous without a real JSON parser.
_state::extract() {
  local kind="$1" raw
  raw="$(_state::raw)"
  [ -n "${raw}" ] || return 0
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
  local key="$1" raw
  raw="$(_state::raw)"
  [ -n "${raw}" ] || return 1
  printf '%s' "${raw}" | tr '\n\r\t' '   ' | awk -v k="${key}" '
    {
      pat = "\"" k "\"[[:space:]]*:";
      if (match($0, pat)) exit 0;
      exit 1;
    }
  '
}

# _state::extract_int <key>: prints integer value of <key>, or empty.
_state::extract_int() {
  local key="$1" raw
  raw="$(_state::raw)"
  [ -n "${raw}" ] || return 0
  printf '%s' "${raw}" | awk -v k="${key}" '
    {
      pat = "\"" k "\"[[:space:]]*:[[:space:]]*-?[0-9]+";
      if (!match($0, pat)) exit;
      rest = substr($0, RSTART, RLENGTH);
      sub(/^[^:]*:[[:space:]]*/, "", rest);
      print rest;
    }
  '
}

_state::extract_swap_active_legacy() {
  local raw
  raw="$(_state::raw)"
  [ -n "${raw}" ] || return 0
  printf '%s' "${raw}" | awk '
    /"swap_active"[[:space:]]*:[[:space:]]*true/ { print "true"; exit }
    /"swap_active"[[:space:]]*:[[:space:]]*false/ { print "false"; exit }
  '
}

# _state::current_swap_alerted_mib: prints the current high-water mark, or 0.
# Migrates schema=1 (swap_active boolean) on read.
_state::current_swap_alerted_mib() {
  local v legacy
  v="$(_state::extract_int swap_alerted_mib)"
  if [ -n "${v}" ]; then
    printf '%s' "${v}"
    return
  fi

  legacy="$(_state::extract_swap_active_legacy)"
  case "${legacy}" in
    true)
      printf '%s' "${MPM_SWAP_THRESHOLD_MIB:-64}"
      return
      ;;
    false)
      printf '0'
      return
      ;;
  esac

  # Backward-compatible inference for state files that predate both fields.
  local last_swap
  last_swap="$(_state::extract swap_in_use)"
  if [ -n "${last_swap}" ]; then
    printf '%s' "${MPM_SWAP_THRESHOLD_MIB:-64}"
  else
    printf '0'
  fi
}

# _state::write_atomic: writes all state in one shot. Atomic via temp file + mv.
_state::write_atomic() {
  local red="$1" warn="$2" swap="$3" swap_alerted_mib="$4"
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

  local red_field warn_field swap_field
  if [ -z "${red}" ]; then red_field='null'; else red_field="\"${red}\""; fi
  if [ -z "${warn}" ]; then warn_field='null'; else warn_field="\"${warn}\""; fi
  if [ -z "${swap}" ]; then swap_field='null'; else swap_field="\"${swap}\""; fi

  case "${swap_alerted_mib}" in
    '' | *[!0-9]*) swap_alerted_mib='0' ;;
  esac

  printf '{"schema":2,"last_alert":{"red_pressure":%s,"warn_pressure":%s,"swap_in_use":%s},"swap_alerted_mib":%s}\n' \
    "${red_field}" "${warn_field}" "${swap_field}" "${swap_alerted_mib}" > "${tmp}"
  mv -f "${tmp}" "${path}"
  if [ "${target_existed}" -eq 0 ]; then
    chmod 0644 "${path}" 2> /dev/null || true
  fi
}

state::should_alert() {
  local kind="$1"
  local cooldown
  cooldown="$(_state::cooldown_for "${kind}")" || return 2

  local raw path
  raw="$(_state::raw)"
  path="$(state::path)"

  # If a state file exists but lacks an expected key, log it as corrupt and
  # treat as "no prior alert" for safety. Both schema 1 and schema 2 expose
  # red_pressure and swap_in_use; warn_pressure is schema 2 only and is
  # tolerated as missing.
  if [ -n "${raw}" ] && [ -f "${path}" ] && {
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
  local kind="$1" swap_mib="${2:-}"
  local now_iso
  now_iso="$(_state::iso_now)"

  local red warn swap swap_alerted_mib
  red="$(_state::extract red_pressure)"
  warn="$(_state::extract warn_pressure)"
  swap="$(_state::extract swap_in_use)"
  swap_alerted_mib="$(_state::current_swap_alerted_mib)"

  case "${kind}" in
    red_pressure) red="${now_iso}" ;;
    warn_pressure) warn="${now_iso}" ;;
    swap_in_use)
      swap="${now_iso}"
      if [ -n "${swap_mib}" ]; then
        case "${swap_mib}" in
          '' | *[!0-9]*) ;;
          *) swap_alerted_mib="${swap_mib}" ;;
        esac
      fi
      ;;
    *) return 2 ;;
  esac

  _state::write_atomic "${red}" "${warn}" "${swap}" "${swap_alerted_mib}"
}

state::swap_alerted_mib() {
  _state::current_swap_alerted_mib
}

state::set_swap_alerted_mib() {
  local desired="$1"
  case "${desired}" in
    '' | *[!0-9]*) return 2 ;;
  esac

  local red warn swap
  red="$(_state::extract red_pressure)"
  warn="$(_state::extract warn_pressure)"
  swap="$(_state::extract swap_in_use)"
  _state::write_atomic "${red}" "${warn}" "${swap}" "${desired}"
}

state::reset() {
  local path
  path="$(state::path)"
  rm -f "${path}"
}
