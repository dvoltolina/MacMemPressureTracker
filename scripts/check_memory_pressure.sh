#!/bin/bash
# scripts/check_memory_pressure.sh — launchd entrypoint.
#
# Sample memory pressure / swap once. If pressure is red or swap is in
# use, fire a debounced notification. Always log the sample.

set -euo pipefail
IFS=$'\n\t'

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"

# shellcheck source=/dev/null
. "${REPO_ROOT}/config/defaults.sh"

if [ -f "${HOME}/.config/memory-pressure-monitor/config.sh" ]; then
  # shellcheck source=/dev/null
  . "${HOME}/.config/memory-pressure-monitor/config.sh"
fi

# shellcheck source=/dev/null
. "${REPO_ROOT}/lib/log.sh"
# shellcheck source=/dev/null
. "${REPO_ROOT}/lib/state.sh"
# shellcheck source=/dev/null
. "${REPO_ROOT}/lib/notify.sh"
# shellcheck source=/dev/null
. "${REPO_ROOT}/lib/pressure.sh"

main() {
  local sample
  if ! sample="$(pressure::sample)"; then
    log::error sample_failed
    exit 1
  fi

  # Pull individual fields for logging.
  local zone free_pct compressed swap_used
  zone="$(printf '%s' "${sample}" | sed -E 's/.*"zone":"([^"]*)".*/\1/')"
  free_pct="$(printf '%s' "${sample}" | sed -E 's/.*"free_pct":([0-9.-]+).*/\1/')"
  compressed="$(printf '%s' "${sample}" | sed -E 's/.*"compressed_pages":([0-9.-]+).*/\1/')"
  swap_used="$(printf '%s' "${sample}" | sed -E 's/.*"swap_used_mib":([0-9.-]+).*/\1/')"

  log::info sample_taken \
    zone="${zone}" \
    free_pct="${free_pct}" \
    compressed_pages="${compressed}" \
    swap_used_mib="${swap_used}"

  if pressure::is_red "${sample}"; then
    if state::should_alert red_pressure; then
      notify::send "Memory pressure: red" \
        "Free ${free_pct}%, ${compressed} compressed pages." \
        "${MPM_NOTIFICATION_SOUND:-}"
      state::record_alert red_pressure
      log::info alert_fired kind=red_pressure
    else
      log::info alert_suppressed kind=red_pressure reason=cooldown
    fi
  fi

  if pressure::swap_in_use "${sample}"; then
    if state::should_alert swap_in_use; then
      notify::send "Swap in use" \
        "Swap used: ${swap_used} MiB." \
        "${MPM_NOTIFICATION_SOUND:-}"
      state::record_alert swap_in_use
      log::info alert_fired kind=swap_in_use
    else
      log::info alert_suppressed kind=swap_in_use reason=cooldown
    fi
  fi
}

main "$@"
