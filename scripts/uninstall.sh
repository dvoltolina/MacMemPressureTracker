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

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
LABEL="com.dominic.memory-pressure-monitor"
PLIST_DEST="${HOME}/Library/LaunchAgents/${LABEL}.plist"

# shellcheck source=/dev/null
. "${REPO_ROOT}/config/defaults.sh"
if [ -f "${HOME}/.config/memory-pressure-monitor/config.sh" ]; then
  # shellcheck source=/dev/null
  . "${HOME}/.config/memory-pressure-monitor/config.sh"
fi

usage() {
  cat <<EOF
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
  state_path="${MPM_STATE_PATH:-${REPO_ROOT}/state/last_alert.json}"
  log_path="${MPM_LOG_PATH:-${HOME}/Library/Logs/memory-pressure-monitor.log}"
  launchd_out="${HOME}/Library/Logs/memory-pressure-monitor.launchd.out.log"
  launchd_err="${HOME}/Library/Logs/memory-pressure-monitor.launchd.err.log"
  for f in "${state_path}" "${log_path}" "${launchd_out}" "${launchd_err}"; do
    if [ -f "${f}" ]; then
      rm -f "${f}"
      printf '✓ purged: %s\n' "${f}"
    fi
  done
  state_dir="$(dirname "${state_path}")"
  if [ -d "${state_dir}" ]; then
    rmdir "${state_dir}" 2> /dev/null || true
  fi
fi

printf '\nuninstall complete.\n'
