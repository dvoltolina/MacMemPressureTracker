#!/bin/bash
# scripts/status.sh — report monitor install and launchd status.

set -Eeuo pipefail
IFS=$'\n\t'

if [ "${MPM_TEST_ALLOW_PATH:-0}" != "1" ]; then
  PATH="/usr/bin:/bin:/usr/sbin:/sbin"
  export PATH
fi

if [ "${EUID}" -eq 0 ]; then
  printf 'do not run status.sh with sudo; run as the logged-in user.\n' >&2
  exit 1
fi

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
LABEL="com.dominic.memory-pressure-monitor"
PLIST_DEST="${HOME}/Library/LaunchAgents/${LABEL}.plist"
DEFAULT_LOG_PATH="${HOME}/Library/Logs/memory-pressure-monitor.log"
DEFAULT_STATE_PATH="${REPO_ROOT}/state/last_alert.json"
LAUNCHD_STDOUT_PATH="${HOME}/Library/Logs/memory-pressure-monitor.launchd.out.log"
LAUNCHD_STDERR_PATH="${HOME}/Library/Logs/memory-pressure-monitor.launchd.err.log"

usage() {
  cat << EOF
Usage: ${0##*/} [--json]

Reports whether the ${LABEL} launchd agent is installed and loaded.

  --json     Emit machine-readable JSON.
  -h --help  Show this help.
EOF
}

mode="human"
while [ $# -gt 0 ]; do
  case "$1" in
    --json) mode="json" ;;
    -h | --help)
      usage
      exit 0
      ;;
    *)
      printf 'unknown flag: %s\n' "$1" >&2
      usage >&2
      exit 2
      ;;
  esac
  shift
done

json_escape() {
  local s="$1"
  s="$(printf '%s' "${s}" | LC_ALL=C tr -d '\001\002\003\004\005\006\007\010\013\014\016\017\020\021\022\023\024\025\026\027\030\031\032\033\034\035\036\037')"
  s="${s//\\/\\\\}"
  s="${s//\"/\\\"}"
  s="${s//$'\t'/\\t}"
  s="${s//$'\r'/\\r}"
  s="${s//$'\n'/\\n}"
  printf '%s' "${s}"
}

yes_no() {
  if [ "$1" = "true" ]; then
    printf 'yes'
  else
    printf 'no'
  fi
}

epoch_now() {
  if [ -n "${TEST_NOW:-}" ]; then
    printf '%s' "${TEST_NOW}"
    return
  fi
  date '+%s'
}

iso_to_epoch() {
  local ts="$1"
  ts="$(printf '%s' "${ts}" | sed 's/\([+-][0-9][0-9]\):\([0-9][0-9]\)$/\1\2/')"
  date -j -f "%Y-%m-%dT%H:%M:%S%z" "${ts}" '+%s' 2> /dev/null
}

json_string_field() {
  local json="$1" key="$2"
  printf '%s' "${json}" | awk -v k="${key}" '
    {
      pat = "\"" k "\":\"";
      idx = index($0, pat);
      if (idx == 0) exit;
      rest = substr($0, idx + length(pat));
      end = index(rest, "\"");
      if (end == 0) exit;
      print substr(rest, 1, end - 1);
    }
  '
}

uid="$(id -u)"
service="gui/${uid}/${LABEL}"

loaded="false"
if launchctl print "${service}" > /dev/null 2>&1; then
  loaded="true"
fi

installed="false"
[ -f "${PLIST_DEST}" ] && installed="true"

config_status="ok"
config_error=""
log_path="${DEFAULT_LOG_PATH}"
state_path="${DEFAULT_STATE_PATH}"

# shellcheck source=/dev/null
. "${REPO_ROOT}/lib/config.sh"
config_error_file="$(mktemp "${TMPDIR:-/tmp}/memory-pressure-status-config.XXXXXX")"
if config::load 2> "${config_error_file}"; then
  log_path="${MPM_LOG_PATH:-${DEFAULT_LOG_PATH}}"
  state_path="${MPM_STATE_PATH:-${DEFAULT_STATE_PATH}}"
else
  config_status="invalid"
  config_error="$(cat "${config_error_file}" 2> /dev/null || true)"
fi
rm -f "${config_error_file}"

log_exists="false"
[ -f "${log_path}" ] && log_exists="true"
log_access="missing"
if [ -L "${log_path}" ]; then
  log_access="unsafe"
elif [ -f "${log_path}" ] && [ -O "${log_path}" ]; then
  log_access="ok"
elif [ -e "${log_path}" ]; then
  log_access="unsafe"
fi

state_exists="false"
[ -f "${state_path}" ] && state_exists="true"

last_log=""
if [ "${log_access}" = "ok" ]; then
  last_log="$(tail -n 1 "${log_path}" 2> /dev/null || true)"
fi

last_sample=""
if [ "${log_access}" = "ok" ]; then
  last_sample="$(grep '"event":"sample_taken"' "${log_path}" 2> /dev/null | tail -n 1 || true)"
fi

last_sample_ts=""
last_sample_epoch=""
sample_age_seconds=""
sample_fresh="false"
case "${MPM_INTERVAL_SECONDS:-30}" in
  '' | *[!0-9]*) interval_for_status=30 ;;
  *) interval_for_status="${MPM_INTERVAL_SECONDS}" ;;
esac
sample_stale_threshold=$((interval_for_status * 3 + 60))
if [ "${sample_stale_threshold}" -lt 120 ]; then
  sample_stale_threshold=120
fi
if [ -n "${last_sample}" ]; then
  last_sample_ts="$(json_string_field "${last_sample}" ts)"
  last_sample_epoch="$(iso_to_epoch "${last_sample_ts}")" || last_sample_epoch=""
  if [ -n "${last_sample_epoch}" ]; then
    sample_age_seconds=$(($(epoch_now) - last_sample_epoch))
    if [ "${sample_age_seconds}" -le "${sample_stale_threshold}" ] && [ "${sample_age_seconds}" -ge 0 ]; then
      sample_fresh="true"
    fi
  fi
fi

last_event=""
last_level=""
if [ -n "${last_log}" ]; then
  last_event="$(json_string_field "${last_log}" event)"
  last_level="$(json_string_field "${last_log}" level)"
fi

launchd_stdout_exists="false"
[ -f "${LAUNCHD_STDOUT_PATH}" ] && launchd_stdout_exists="true"
launchd_stderr_exists="false"
[ -f "${LAUNCHD_STDERR_PATH}" ] && launchd_stderr_exists="true"

last_launchd_stdout=""
if [ -f "${LAUNCHD_STDOUT_PATH}" ]; then
  last_launchd_stdout="$(tail -n 1 "${LAUNCHD_STDOUT_PATH}" 2> /dev/null || true)"
fi

last_launchd_stderr=""
if [ -f "${LAUNCHD_STDERR_PATH}" ]; then
  last_launchd_stderr="$(tail -n 1 "${LAUNCHD_STDERR_PATH}" 2> /dev/null || true)"
fi

health="not_installed"
health_label="Not installed"
if [ "${config_status}" = "invalid" ]; then
  health="config_invalid"
  health_label="Config invalid"
elif [ "${loaded}" = "true" ] && { [ "${last_level}" = "error" ] || [ "${last_event}" = "sample_failed" ]; }; then
  health="loaded_error"
  health_label="Loaded, last event failed"
elif [ "${loaded}" = "true" ] && [ "${sample_fresh}" = "true" ]; then
  health="running"
  health_label="Running"
elif [ "${loaded}" = "true" ] && [ -n "${last_sample}" ]; then
  health="loaded_stale_sample"
  health_label="Loaded, sample stale"
elif [ "${loaded}" = "true" ]; then
  health="loaded_no_sample"
  health_label="Loaded, no sample logged"
elif [ "${installed}" = "true" ]; then
  health="installed_not_loaded"
  health_label="Installed, not loaded"
fi

if [ "${mode}" = "json" ]; then
  printf '{'
  printf '"label":"%s",' "$(json_escape "${LABEL}")"
  printf '"service":"%s",' "$(json_escape "${service}")"
  printf '"health":"%s",' "$(json_escape "${health}")"
  printf '"health_label":"%s",' "$(json_escape "${health_label}")"
  printf '"loaded":%s,' "${loaded}"
  printf '"installed":%s,' "${installed}"
  printf '"plist_path":"%s",' "$(json_escape "${PLIST_DEST}")"
  printf '"config_status":"%s",' "$(json_escape "${config_status}")"
  printf '"config_error":"%s",' "$(json_escape "${config_error}")"
  printf '"log_path":"%s",' "$(json_escape "${log_path}")"
  printf '"log_exists":%s,' "${log_exists}"
  printf '"log_access":"%s",' "$(json_escape "${log_access}")"
  printf '"state_path":"%s",' "$(json_escape "${state_path}")"
  printf '"state_exists":%s,' "${state_exists}"
  printf '"last_log":"%s",' "$(json_escape "${last_log}")"
  printf '"last_sample":"%s",' "$(json_escape "${last_sample}")"
  if [ -n "${sample_age_seconds}" ]; then
    printf '"sample_age_seconds":%s,' "${sample_age_seconds}"
  else
    printf '"sample_age_seconds":null,'
  fi
  printf '"sample_fresh":%s,' "${sample_fresh}"
  printf '"sample_stale_threshold_seconds":%s,' "${sample_stale_threshold}"
  printf '"launchd_stdout_path":"%s",' "$(json_escape "${LAUNCHD_STDOUT_PATH}")"
  printf '"launchd_stdout_exists":%s,' "${launchd_stdout_exists}"
  printf '"last_launchd_stdout":"%s",' "$(json_escape "${last_launchd_stdout}")"
  printf '"launchd_stderr_path":"%s",' "$(json_escape "${LAUNCHD_STDERR_PATH}")"
  printf '"launchd_stderr_exists":%s,' "${launchd_stderr_exists}"
  printf '"last_launchd_stderr":"%s"' "$(json_escape "${last_launchd_stderr}")"
  printf '}\n'
  exit 0
fi

cat << EOF
Memory Pressure Monitor

Status:          ${health_label}
Launchd loaded:  $(yes_no "${loaded}")
Plist installed: $(yes_no "${installed}")
Service:         ${service}
Plist:           ${PLIST_DEST}

Config:          ${config_status}
Log file:        $(yes_no "${log_exists}") [${log_access}] (${log_path})
State file:      $(yes_no "${state_exists}") (${state_path})
Launchd stdout:  $(yes_no "${launchd_stdout_exists}") (${LAUNCHD_STDOUT_PATH})
Launchd stderr:  $(yes_no "${launchd_stderr_exists}") (${LAUNCHD_STDERR_PATH})
Sample fresh:    $(yes_no "${sample_fresh}") (${sample_age_seconds:-unknown}s old, threshold ${sample_stale_threshold}s)
EOF

if [ -n "${config_error}" ]; then
  printf '\nConfig error:\n%s\n' "${config_error}"
fi

if [ -n "${last_sample}" ]; then
  printf '\nLast sample:\n%s\n' "${last_sample}"
else
  printf '\nLast sample:\n(none yet)\n'
fi

if [ -n "${last_log}" ]; then
  printf '\nLast event:\n%s\n' "${last_log}"
else
  printf '\nLast event:\n(none yet)\n'
fi

if [ -n "${last_launchd_stderr}" ]; then
  printf '\nLast launchd error line:\n%s\n' "${last_launchd_stderr}"
fi
