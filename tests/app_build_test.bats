#!/usr/bin/env bats
# Smoke test for the native dashboard app build.

setup() {
  REPO_ROOT="$(cd "${BATS_TEST_DIRNAME}/.." && pwd)"
}

@test "build-app creates a valid app bundle" {
  run "${REPO_ROOT}/scripts/build-app.sh"
  [ "$status" -eq 0 ]
  [ -x "${REPO_ROOT}/build/Memory Pressure Monitor.app/Contents/MacOS/Memory Pressure Monitor" ]
  [ -s "${REPO_ROOT}/build/Memory Pressure Monitor.app/Contents/Resources/AppIcon.icns" ]

  if command -v plutil > /dev/null 2>&1; then
    run plutil -lint "${REPO_ROOT}/build/Memory Pressure Monitor.app/Contents/Info.plist"
    [ "$status" -eq 0 ]
  fi
}

@test "build-app removes stale nested symlinked bundle directories safely" {
  target="${BATS_TEST_TMPDIR}/outside-resources"
  mkdir -p "${REPO_ROOT}/build/Memory Pressure Monitor.app/Contents" "${target}"
  ln -s "${target}" "${REPO_ROOT}/build/Memory Pressure Monitor.app/Contents/Resources"

  run "${REPO_ROOT}/scripts/build-app.sh"
  [ "$status" -eq 0 ]
  [ -s "${REPO_ROOT}/build/Memory Pressure Monitor.app/Contents/Resources/AppIcon.icns" ]
  [ ! -e "${target}/AppIcon.icns" ]
}
