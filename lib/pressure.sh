# lib/pressure.sh — memory pressure / swap parser.
#
# Sourced, never executed.
#
# Tested against macOS 26.1 (build 25B78). Earlier versions are believed
# to use the same sysctl OIDs and vm_stat layout but are not certified.
#
# Primitives (read via _pressure::_invoke_external — stubbable in tests):
#   sysctl kern.memorystatus_vm_pressure_level   -> 1=normal, 2=warn, 4=critical
#   sysctl kern.memorystatus_level               -> integer free percentage
#   sysctl vm.swapusage                          -> "vm.swapusage: total = X.YYM used = X.YYM free = X.YYM ..."
#   vm_stat                                       -> "Pages occupied by compressor: <N>." among many lines
#
# Public API:
#   pressure::sample            -> prints one JSON line on stdout
#   pressure::is_red    <json>  -> exit 0 if zone == red, else 1
#   pressure::swap_in_use <json> -> exit 0 if swap_used_mib >= MPM_SWAP_THRESHOLD_MIB, else 1

# shellcheck shell=bash

# Map sysctl pressure level integer to canonical zone label.
# Unknown values map to "normal" so we don't notify on noise.
_pressure::zone_from_level() {
  case "$1" in
    1) printf 'normal' ;;
    2) printf 'warn' ;;
    4) printf 'red' ;;
    *) return 1 ;;
  esac
}

# _pressure::_invoke_external <key>
# The single chokepoint that runs real external commands. Tests stub
# this function to feed fixture content instead.
_pressure::_invoke_external() {
  case "$1" in
    pressure_level) sysctl kern.memorystatus_vm_pressure_level 2> /dev/null ;;
    free_level) sysctl kern.memorystatus_level 2> /dev/null ;;
    swapusage) sysctl vm.swapusage 2> /dev/null ;;
    vm_stat) vm_stat 2> /dev/null ;;
    *) return 2 ;;
  esac
}

# pressure::parse_pressure_level
# stdin: line like "kern.memorystatus_vm_pressure_level: 1"
# stdout: integer value (1/2/4/...) or empty on failure.
# return: 0 on success, 1 on parse error.
pressure::parse_pressure_level() {
  local line val
  line="$(cat)"
  val="$(printf '%s\n' "${line}" | awk -F': *' '/memorystatus_vm_pressure_level/ {print $2; exit}')"
  case "${val}" in
    '' | *[!0-9]*) return 1 ;;
    *) printf '%s' "${val}" ;;
  esac
}

# pressure::parse_free_level
# stdin: line like "kern.memorystatus_level: 53"
# stdout: integer percentage. return 1 on parse error.
pressure::parse_free_level() {
  local line val
  line="$(cat)"
  val="$(printf '%s\n' "${line}" | awk -F': *' '/memorystatus_level/ {print $2; exit}')"
  case "${val}" in
    '' | *[!0-9]*) return 1 ;;
    *) printf '%s' "${val}" ;;
  esac
}

# pressure::parse_swap
# stdin: "vm.swapusage: total = 4096.00M  used = 2806.88M  free = 1289.12M  (encrypted)"
# stdout: used MiB rounded down to integer (e.g. 2806). return 1 on parse error.
pressure::parse_swap() {
  local line used
  line="$(cat)"
  used="$(printf '%s\n' "${line}" | awk -F'used = ' '/vm\.swapusage/ {split($2, a, "M"); print a[1]; exit}')"
  case "${used}" in
    '' | *[!0-9.]*) return 1 ;;
  esac
  # Drop fractional part. awk handles that portably.
  printf '%s' "${used}" | awk '{printf "%d", $1}'
}

# pressure::parse_compressed
# stdin: full vm_stat output.
# stdout: integer "Pages occupied by compressor". return 1 on parse error.
pressure::parse_compressed() {
  local line val
  line="$(cat)"
  val="$(printf '%s\n' "${line}" | awk -F': *' '/Pages occupied by compressor/ {gsub(/[^0-9]/, "", $2); print $2; exit}')"
  case "${val}" in
    '' | *[!0-9]*) return 1 ;;
    *) printf '%s' "${val}" ;;
  esac
}

# pressure::sample
# Emits one JSON line:
#   {"zone":"normal|warn|red","free_pct":<int>,"compressed_pages":<int>,"swap_used_mib":<int>}
# Returns non-zero if the primary pressure-level primitive fails, reports
# an unknown enum, or swap output cannot be parsed. Non-swap secondary
# fields default to 0 on failure.
pressure::sample() {
  local raw_level zone free_pct compressed swap_used

  if ! raw_level="$(_pressure::_invoke_external pressure_level | pressure::parse_pressure_level)"; then
    return 1
  fi
  if ! zone="$(_pressure::zone_from_level "${raw_level}")"; then
    return 1
  fi

  free_pct="$(_pressure::_invoke_external free_level | pressure::parse_free_level)" || free_pct="0"
  compressed="$(_pressure::_invoke_external vm_stat | pressure::parse_compressed)" || compressed="0"
  if ! swap_used="$(_pressure::_invoke_external swapusage | pressure::parse_swap)"; then
    return 1
  fi

  printf '{"zone":"%s","free_pct":%s,"compressed_pages":%s,"swap_used_mib":%s}\n' \
    "${zone}" "${free_pct}" "${compressed}" "${swap_used}"
}

# _pressure::field <json> <key>
# Tiny extractor. Pure regex; not a general JSON parser.
_pressure::field() {
  local json="$1" key="$2"
  printf '%s' "${json}" | awk -v k="${key}" '
    {
      n = split($0, parts, ",");
      for (i = 1; i <= n; i++) {
        sub(/^[{[:space:]]+/, "", parts[i]);
        sub(/[}[:space:]]+$/, "", parts[i]);
        if (split(parts[i], kv, ":") < 2) continue;
        gsub(/"/, "", kv[1]);
        if (kv[1] == k) {
          val = parts[i];
          sub(/^[^:]*:/, "", val);
          gsub(/^[[:space:]"]+|[[:space:]"]+$/, "", val);
          print val;
          exit;
        }
      }
    }
  '
}

pressure::is_red() {
  local zone
  zone="$(_pressure::field "$1" zone)"
  [ "${zone}" = "red" ]
}

pressure::is_warn() {
  local zone
  zone="$(_pressure::field "$1" zone)"
  [ "${zone}" = "warn" ]
}

pressure::swap_in_use() {
  local used threshold
  used="$(_pressure::field "$1" swap_used_mib)"
  threshold="${MPM_SWAP_THRESHOLD_MIB:-64}"
  [ -n "${used}" ] || return 1
  [ "${used}" -ge "${threshold}" ]
}
