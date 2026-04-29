#!/bin/bash
# scripts/uninstall.sh — bootout the agent and remove its plist.
#
# Flags:
#   --purge     also remove state file and log files
#   -h --help   usage
#
# Idempotent: running twice is safe.

set -Eeuo pipefail
IFS=$'\n\t'

if [ "${MPM_TEST_ALLOW_PATH:-0}" != "1" ]; then
  PATH="/usr/bin:/bin:/usr/sbin:/sbin"
  export PATH
fi

LABEL="com.dominic.memory-pressure-monitor"
PLIST_DEST="${HOME}/Library/LaunchAgents/${LABEL}.plist"

usage() {
  cat << EOF
Usage: ${0##*/} [--purge]

Stops and removes the ${LABEL} launchd agent.

  --purge     Also remove state file and log files (irreversible).
  -h --help   Show this help.
EOF
}

purge=0
while [ $# -gt 0 ]; do
  case "$1" in
    --purge) purge=1 ;;
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

if [ "${EUID}" -eq 0 ]; then
  printf 'do not run uninstall.sh with sudo; uninstall as the logged-in user.\n' >&2
  exit 1
fi

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"

uid="$(id -u)"
domain="gui/${uid}"
service="${domain}/${LABEL}"

# Bootout if loaded.
if launchctl print "${service}" > /dev/null 2>&1; then
  launchctl bootout "${service}" 2> /dev/null || true
  printf '✓ booted out: %s\n' "${LABEL}"
else
  printf '  not loaded: %s\n' "${LABEL}"
fi

# Remove plist.
if [ -f "${PLIST_DEST}" ]; then
  rm -f "${PLIST_DEST}"
  printf '✓ removed plist: %s\n' "${PLIST_DEST}"
else
  printf '  no plist:        %s\n' "${PLIST_DEST}"
fi

if [ "${purge}" -eq 1 ]; then
  default_state_path="${REPO_ROOT}/state/last_alert.json"
  default_log_path="${HOME}/Library/Logs/memory-pressure-monitor.log"
  configured_state_path="${default_state_path}"
  configured_log_path="${default_log_path}"
  # shellcheck source=/dev/null
  if . "${REPO_ROOT}/lib/config.sh" && config::load; then
    configured_state_path="${MPM_STATE_PATH:-${default_state_path}}"
    configured_log_path="${MPM_LOG_PATH:-${default_log_path}}"
  else
    printf 'warning: config is invalid; purging only default app-owned paths.\n' >&2
  fi
  launchd_out="${HOME}/Library/Logs/memory-pressure-monitor.launchd.out.log"
  launchd_err="${HOME}/Library/Logs/memory-pressure-monitor.launchd.err.log"
  for f in "${default_state_path}" "${default_log_path}" "${launchd_out}" "${launchd_err}"; do
    if [ -f "${f}" ]; then
      rm -f "${f}"
      printf '✓ purged: %s\n' "${f}"
    fi
  done
  if [ "${configured_state_path}" != "${default_state_path}" ]; then
    printf '  skipped configured state path outside default purge scope: %s\n' "${configured_state_path}"
  fi
  if [ "${configured_log_path}" != "${default_log_path}" ]; then
    printf '  skipped configured log path outside default purge scope: %s\n' "${configured_log_path}"
  fi
  state_dir="$(dirname "${default_state_path}")"
  if [ -d "${state_dir}" ]; then
    rmdir "${state_dir}" 2> /dev/null || true
  fi
fi

printf '\nuninstall complete.\n'
