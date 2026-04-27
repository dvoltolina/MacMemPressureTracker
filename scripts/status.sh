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

usage() {
  cat <<EOF
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
if config_output="$(config::load 2>&1)"; then
  log_path="${MPM_LOG_PATH:-${DEFAULT_LOG_PATH}}"
  state_path="${MPM_STATE_PATH:-${DEFAULT_STATE_PATH}}"
else
  config_status="invalid"
  config_error="${config_output}"
fi

log_exists="false"
[ -f "${log_path}" ] && log_exists="true"

state_exists="false"
[ -f "${state_path}" ] && state_exists="true"

last_log=""
if [ -f "${log_path}" ]; then
  last_log="$(tail -n 1 "${log_path}" 2> /dev/null || true)"
fi

if [ "${mode}" = "json" ]; then
  printf '{'
  printf '"label":"%s",' "$(json_escape "${LABEL}")"
  printf '"service":"%s",' "$(json_escape "${service}")"
  printf '"loaded":%s,' "${loaded}"
  printf '"installed":%s,' "${installed}"
  printf '"plist_path":"%s",' "$(json_escape "${PLIST_DEST}")"
  printf '"config_status":"%s",' "$(json_escape "${config_status}")"
  printf '"config_error":"%s",' "$(json_escape "${config_error}")"
  printf '"log_path":"%s",' "$(json_escape "${log_path}")"
  printf '"log_exists":%s,' "${log_exists}"
  printf '"state_path":"%s",' "$(json_escape "${state_path}")"
  printf '"state_exists":%s,' "${state_exists}"
  printf '"last_log":"%s"' "$(json_escape "${last_log}")"
  printf '}\n'
  exit 0
fi

cat <<EOF
Memory Pressure Monitor

Launchd loaded:  $(yes_no "${loaded}")
Plist installed: $(yes_no "${installed}")
Service:         ${service}
Plist:           ${PLIST_DEST}

Config:          ${config_status}
Log file:        $(yes_no "${log_exists}") (${log_path})
State file:      $(yes_no "${state_exists}") (${state_path})
EOF

if [ -n "${config_error}" ]; then
  printf '\nConfig error:\n%s\n' "${config_error}"
fi

if [ -n "${last_log}" ]; then
  printf '\nLast log line:\n%s\n' "${last_log}"
else
  printf '\nLast log line:\n(none yet)\n'
fi
