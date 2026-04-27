#!/bin/bash
# scripts/build-app.sh — compile the native dashboard app bundle.

set -Eeuo pipefail
IFS=$'\n\t'

if [ "${MPM_TEST_ALLOW_PATH:-0}" != "1" ]; then
  PATH="/usr/bin:/bin:/usr/sbin:/sbin"
  export PATH
fi

if [ "${EUID}" -eq 0 ]; then
  printf 'do not run build-app.sh with sudo; build as the logged-in user.\n' >&2
  exit 1
fi

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
APP_NAME="Memory Pressure Monitor"
APP_SOURCE_DIR="${REPO_ROOT}/app/MemoryPressureMonitor"
BUILD_DIR="${REPO_ROOT}/build"
APP_DIR="${BUILD_DIR}/${APP_NAME}.app"
CONTENTS_DIR="${APP_DIR}/Contents"
MACOS_DIR="${CONTENTS_DIR}/MacOS"
RESOURCES_DIR="${CONTENTS_DIR}/Resources"
EXECUTABLE="${APP_NAME}"

require_tool() {
  if ! command -v "$1" > /dev/null 2>&1; then
    printf 'required tool not found: %s\n' "$1" >&2
    printf 'Install Xcode Command Line Tools with: xcode-select --install\n' >&2
    exit 1
  fi
}

xml_escape() {
  printf '%s' "$1" | sed \
    -e 's/&/\&amp;/g' \
    -e 's/</\&lt;/g' \
    -e 's/>/\&gt;/g'
}

sed_replacement_escape() {
  printf '%s' "$1" | sed 's/[\\&#]/\\&/g'
}

plist_value() {
  sed_replacement_escape "$(xml_escape "$1")"
}

require_tool swiftc
require_tool iconutil
require_tool plutil

if [ -L "${BUILD_DIR}" ] || [ -L "${APP_DIR}" ]; then
  printf 'refusing to build through symlinked build path\n' >&2
  exit 1
fi

if [ -e "${APP_DIR}" ]; then
  rm -rf "${APP_DIR}"
fi

mkdir -p "${MACOS_DIR}" "${RESOURCES_DIR}"

icon_parent="$(mktemp -d "${TMPDIR:-/tmp}/memory-pressure-monitor-icon.XXXXXX")"
cleanup() {
  rm -rf "${icon_parent}"
}
trap cleanup EXIT

iconset="${icon_parent}/AppIcon.iconset"
icon_factory_bin="${icon_parent}/IconFactory"

swiftc \
  "${APP_SOURCE_DIR}/IconFactory.swift" \
  -framework AppKit \
  -o "${icon_factory_bin}"

"${icon_factory_bin}" "${iconset}"
iconutil -c icns "${iconset}" -o "${RESOURCES_DIR}/AppIcon.icns"

swiftc \
  -parse-as-library \
  "${APP_SOURCE_DIR}/AppDelegate.swift" \
  -framework AppKit \
  -o "${MACOS_DIR}/${EXECUTABLE}"

sed \
  -e "s#__EXECUTABLE__#$(plist_value "${EXECUTABLE}")#g" \
  -e "s#__REPO_ROOT__#$(plist_value "${REPO_ROOT}")#g" \
  "${APP_SOURCE_DIR}/Info.plist.tmpl" > "${CONTENTS_DIR}/Info.plist"

chmod 0755 "${MACOS_DIR}/${EXECUTABLE}"
plutil -lint "${CONTENTS_DIR}/Info.plist" > /dev/null

printf 'built app: %s\n' "${APP_DIR}"
