#!/bin/bash
# scripts/install.sh — render plist + launchctl bootstrap.
#
# Flags:
#   --dry-run   render plist to stdout, do not install
#   --force     replace an already-loaded label (bootout first)
#   -h --help   usage
#
# Idempotency: if the agent is already loaded with identical content,
# install is a no-op. With --force, the existing instance is booted out
# and reloaded.

set -Eeuo pipefail
IFS=$'\n\t'

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
LABEL="com.dominic.memory-pressure-monitor"
TEMPLATE="${REPO_ROOT}/launchd/${LABEL}.plist.tmpl"
PLIST_DEST="${HOME}/Library/LaunchAgents/${LABEL}.plist"
LOG_DIR="${HOME}/Library/Logs"

# shellcheck source=/dev/null
. "${REPO_ROOT}/lib/config.sh"
config::load

usage() {
  cat <<EOF
Usage: ${0##*/} [--dry-run] [--force]

Renders the launchd plist for ${LABEL} and bootstraps the agent.

  --dry-run   Print the rendered plist to stdout and exit.
  --force     Replace an already-loaded label (bootout first).
  -h --help   Show this help.
EOF
}

dry_run=0
force=0
while [ $# -gt 0 ]; do
  case "$1" in
    --dry-run) dry_run=1 ;;
    --force) force=1 ;;
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

if [ "$(id -u)" -eq 0 ]; then
  printf 'do not run install.sh with sudo; install as the logged-in user.\n' >&2
  exit 1
fi

if [ ! -f "${TEMPLATE}" ]; then
  printf 'template not found: %s\n' "${TEMPLATE}" >&2
  exit 1
fi

# Reject template-hostile values up front.
hostile() {
  case "$1" in
    *']]>'*) return 0 ;;
    *'<'*) return 0 ;;
    *'>'*) return 0 ;;
    *'&'*) return 0 ;;
    *) return 1 ;;
  esac
}

PROGRAM="${REPO_ROOT}/scripts/check_memory_pressure.sh"
WORKING_DIR="${REPO_ROOT}"
INTERVAL="${MPM_INTERVAL_SECONDS:-30}"
STDOUT="${LOG_DIR}/memory-pressure-monitor.launchd.out.log"
STDERR="${LOG_DIR}/memory-pressure-monitor.launchd.err.log"

for v in "${PROGRAM}" "${WORKING_DIR}" "${STDOUT}" "${STDERR}" "${HOME}"; do
  if hostile "${v}"; then
    printf 'value contains XML-hostile characters: %s\n' "${v}" >&2
    exit 1
  fi
done

case "${INTERVAL}" in
  '' | *[!0-9]*)
    printf 'MPM_INTERVAL_SECONDS must be a positive integer, got: %s\n' "${INTERVAL}" >&2
    exit 1
    ;;
esac

# Render template.
rendered="$(
  sed \
    -e "s#__LABEL__#${LABEL}#g" \
    -e "s#__PROGRAM__#${PROGRAM}#g" \
    -e "s#__WORKING_DIR__#${WORKING_DIR}#g" \
    -e "s#__INTERVAL__#${INTERVAL}#g" \
    -e "s#__STDOUT__#${STDOUT}#g" \
    -e "s#__STDERR__#${STDERR}#g" \
    -e "s#__HOME__#${HOME}#g" \
    "${TEMPLATE}"
)"

if [ "${dry_run}" -eq 1 ]; then
  printf '%s\n' "${rendered}"
  exit 0
fi

# Verify the entrypoint is executable.
if [ ! -x "${PROGRAM}" ]; then
  printf 'entrypoint not executable: %s\n' "${PROGRAM}" >&2
  printf 'fix with: chmod +x "%s"\n' "${PROGRAM}" >&2
  exit 1
fi

mkdir -p "${LOG_DIR}"
mkdir -p "$(dirname "${PLIST_DEST}")"

# Write plist atomically.
tmp_plist="${PLIST_DEST}.tmp.$$"
printf '%s\n' "${rendered}" > "${tmp_plist}"

# Validate plist syntax if plutil is available.
if command -v plutil > /dev/null 2>&1; then
  if ! plutil -lint "${tmp_plist}" > /dev/null; then
    printf 'rendered plist failed plutil -lint:\n' >&2
    plutil -lint "${tmp_plist}" >&2 || true
    rm -f "${tmp_plist}"
    exit 1
  fi
fi

# Decide bootstrap path based on whether label is already loaded.
uid="$(id -u)"
domain="gui/${uid}"
service="${domain}/${LABEL}"

already_loaded=0
if launchctl print "${service}" > /dev/null 2>&1; then
  already_loaded=1
fi

if [ "${already_loaded}" -eq 1 ]; then
  if [ "${force}" -eq 0 ]; then
    if cmp -s "${tmp_plist}" "${PLIST_DEST}" 2> /dev/null; then
      rm -f "${tmp_plist}"
      printf 'agent already loaded with identical config; nothing to do.\n'
      printf 'use --force to reload anyway.\n'
      exit 0
    fi
    rm -f "${tmp_plist}"
    printf 'agent is already loaded but plist content differs.\n' >&2
    printf 'pass --force to bootout and reload.\n' >&2
    exit 1
  fi
  launchctl bootout "${service}" 2> /dev/null || true
fi

mv -f "${tmp_plist}" "${PLIST_DEST}"
chmod 0644 "${PLIST_DEST}"

if ! launchctl bootstrap "${domain}" "${PLIST_DEST}"; then
  printf 'launchctl bootstrap failed for %s\n' "${PLIST_DEST}" >&2
  exit 1
fi

# Verify.
if launchctl print "${service}" > /dev/null 2>&1; then
  printf '✓ installed: %s\n' "${LABEL}"
  printf '  plist:      %s\n' "${PLIST_DEST}"
  printf '  interval:   %ss\n' "${INTERVAL}"
  printf '  log:        %s\n' "${MPM_LOG_PATH:-${HOME}/Library/Logs/memory-pressure-monitor.log}"
  printf '\nFirst notification will require macOS notification permission. The first time the\n'
  printf 'agent fires a notification, macOS may show a system prompt — approve it to receive\n'
  printf 'future alerts.\n'
else
  printf 'install completed but launchctl print failed; check Console.app for errors\n' >&2
  exit 1
fi
