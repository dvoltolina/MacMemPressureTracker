#!/bin/bash
# scripts/check_memory_pressure.sh — launchd entrypoint.
#
# Sample memory pressure / swap once. If pressure is red or swap is in
# use, fire a debounced notification. Always log the sample.

set -Eeuo pipefail
IFS=$'\n\t'

if [ "${MPM_TEST_ALLOW_PATH:-0}" != "1" ]; then
  PATH="/usr/bin:/bin:/usr/sbin:/sbin"
  export PATH
fi

if [ "${EUID}" -eq 0 ]; then
  printf 'do not run check_memory_pressure.sh with sudo; run as the logged-in user.\n' >&2
  exit 1
fi

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"

# shellcheck source=/dev/null
. "${REPO_ROOT}/lib/config.sh"
config::load
# shellcheck source=/dev/null
. "${REPO_ROOT}/lib/log.sh"
trap 'log::error tick_failed line="${LINENO}" cmd="${BASH_COMMAND}"' ERR
# shellcheck source=/dev/null
. "${REPO_ROOT}/lib/state.sh"
# shellcheck source=/dev/null
. "${REPO_ROOT}/lib/notify.sh"
# shellcheck source=/dev/null
. "${REPO_ROOT}/lib/pressure.sh"

send_alert() {
  local kind="$1" title="$2" body="$3"

  if notify::send "${title}" "${body}" "${MPM_NOTIFICATION_SOUND:-}"; then
    log::info alert_fired kind="${kind}"
  else
    log::warn alert_failed kind="${kind}"
  fi

  # Record attempts, not only successful deliveries. A denied or failing
  # notification backend should not retry every launchd tick.
  state::record_alert "${kind}"
}

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

  local red_active swap_now red_attempted
  red_active=0
  swap_now=0
  red_attempted=0

  if pressure::is_red "${sample}"; then
    red_active=1
  fi
  if pressure::swap_in_use "${sample}"; then
    swap_now=1
  fi

  if [ "${red_active}" -eq 1 ]; then
    if state::should_alert red_pressure; then
      red_attempted=1
      send_alert red_pressure \
        "Memory pressure critical" \
        "Free ${free_pct}%; swap ${swap_used} MiB. Close high-memory apps."
    else
      log::info alert_suppressed kind=red_pressure reason=cooldown
    fi
  fi

  if [ "${swap_now}" -eq 1 ]; then
    if state::swap_active; then
      log::info alert_suppressed kind=swap_in_use reason=still_active
    elif [ "${red_attempted}" -eq 1 ]; then
      state::record_alert swap_in_use
      log::info alert_coalesced kind=swap_in_use into=red_pressure
    elif state::should_alert swap_in_use; then
      send_alert swap_in_use \
        "Swap in use" \
        "Swap is ${swap_used} MiB (threshold ${MPM_SWAP_THRESHOLD_MIB} MiB). Close high-memory apps."
    else
      state::set_swap_active true
      log::info alert_suppressed kind=swap_in_use reason=cooldown
    fi
  elif state::swap_active; then
    state::set_swap_active false
    log::info swap_cleared
  fi
}

main "$@"
