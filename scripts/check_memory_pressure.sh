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
  local zone="${4:-}" free_pct="${5:-}" swap_mib="${6:-}"

  local extra=()
  [ -n "${zone}" ] && extra+=(--zone "${zone}")
  [ -n "${free_pct}" ] && extra+=(--free-pct "${free_pct}")
  [ -n "${swap_mib}" ] && extra+=(--swap-mib "${swap_mib}")

  if notify::send "${title}" "${body}" "${MPM_NOTIFICATION_SOUND:-}" "${kind}" "${extra[@]+"${extra[@]}"}"; then
    log::info alert_fired kind="${kind}"
  else
    log::warn alert_failed kind="${kind}"
  fi

  # Record attempts, not only successful deliveries. A denied or failing
  # notification backend should not retry every launchd tick.
  if [ "${kind}" = "swap_in_use" ] && [ -n "${swap_mib}" ]; then
    state::record_alert "${kind}" "${swap_mib}"
  else
    state::record_alert "${kind}"
  fi
}

main() {
  local sample
  if ! sample="$(pressure::sample)"; then
    log::error sample_failed
    exit 1
  fi

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

  local red_active warn_active swap_now red_attempted warn_attempted
  red_active=0
  warn_active=0
  swap_now=0
  red_attempted=0
  warn_attempted=0

  if pressure::is_red "${sample}"; then
    red_active=1
  fi
  if pressure::is_warn "${sample}"; then
    warn_active=1
  fi
  if pressure::swap_in_use "${sample}"; then
    swap_now=1
  fi

  if [ "${red_active}" -eq 1 ]; then
    if state::should_alert red_pressure; then
      red_attempted=1
      send_alert red_pressure \
        "Memory pressure critical" \
        "Free ${free_pct}%; swap ${swap_used} MiB. Close high-memory apps." \
        "${zone}" "${free_pct}" "${swap_used}"
    else
      log::info alert_suppressed kind=red_pressure reason=cooldown
    fi
  elif [ "${warn_active}" -eq 1 ] && [ "${MPM_WARN_ALERTS_ENABLED:-1}" = "1" ]; then
    if state::should_alert warn_pressure; then
      warn_attempted=1
      send_alert warn_pressure \
        "Memory pressure rising" \
        "Free ${free_pct}%; swap ${swap_used} MiB. Consider closing apps." \
        "${zone}" "${free_pct}" "${swap_used}"
    else
      log::info alert_suppressed kind=warn_pressure reason=cooldown
    fi
  fi

  if [ "${swap_now}" -eq 1 ]; then
    local prev_alerted growth_threshold
    prev_alerted="$(state::swap_alerted_mib)"
    # Defensive default: state::swap_alerted_mib always prints something,
    # but keep this in case a future refactor lets it return empty under
    # `set -u`. Without the default, the arithmetic below would abort the
    # tick.
    prev_alerted="${prev_alerted:-0}"
    growth_threshold="${MPM_SWAP_GROWTH_MIB:-1024}"

    local should_fire_swap=0 fire_reason=""
    if [ "${prev_alerted}" -eq 0 ]; then
      should_fire_swap=1
      fire_reason="first_observed"
    elif [ "$((swap_used - prev_alerted))" -ge "${growth_threshold}" ]; then
      should_fire_swap=1
      fire_reason="growth"
    fi

    if [ "${should_fire_swap}" -eq 1 ]; then
      if [ "${red_attempted}" -eq 1 ] || [ "${warn_attempted}" -eq 1 ]; then
        state::record_alert swap_in_use "${swap_used}"
        log::info alert_coalesced kind=swap_in_use into=pressure swap_used_mib="${swap_used}"
      elif state::should_alert swap_in_use; then
        send_alert swap_in_use \
          "Swap in use" \
          "Swap is ${swap_used} MiB (was ${prev_alerted} MiB). Close high-memory apps." \
          "${zone}" "${free_pct}" "${swap_used}"
        log::info swap_alert_reason reason="${fire_reason}" prev_mib="${prev_alerted}" now_mib="${swap_used}"
      else
        log::info alert_suppressed kind=swap_in_use reason=cooldown
      fi
    else
      log::info alert_suppressed kind=swap_in_use reason=below_growth_threshold prev_mib="${prev_alerted}" now_mib="${swap_used}"
    fi
  else
    # Swap returned to (effectively) zero. Reset the high-water mark so the
    # next time swap appears, we treat it as a fresh first-observed event.
    if [ "$(state::swap_alerted_mib)" -ne 0 ]; then
      state::set_swap_alerted_mib 0
      log::info swap_cleared
    fi
  fi
}

main "$@"
