#!/usr/bin/env bats
# Tests for scripts/install.sh dry-run rendering.

setup() {
  REPO_ROOT="$(cd "${BATS_TEST_DIRNAME}/.." && pwd)"
  TMP="$(mktemp -d)"
  export HOME="${TMP}/home"
  export MPM_CONFIG_PATH="${TMP}/missing-config.sh"
  mkdir -p "${HOME}"
}

teardown() {
  rm -rf "${TMP}"
}

@test "install --dry-run renders plist without launchctl side effects" {
  run "${REPO_ROOT}/scripts/install.sh" --dry-run
  [ "$status" -eq 0 ]
  [[ "$output" == *"<key>Label</key>"* ]]
  [[ "$output" == *"com.dominic.memory-pressure-monitor"* ]]
  [[ "$output" == *"${REPO_ROOT}/scripts/check_memory_pressure.sh"* ]]
  [[ "$output" == *"<integer>30</integer>"* ]]
}

@test "install --dry-run honors strict config interval" {
  cat > "${TMP}/config.sh" <<'CFG'
MPM_INTERVAL_SECONDS=45
CFG
  export MPM_CONFIG_PATH="${TMP}/config.sh"

  run "${REPO_ROOT}/scripts/install.sh" --dry-run
  [ "$status" -eq 0 ]
  [[ "$output" == *"<integer>45</integer>"* ]]
}

@test "install --help works when user config is invalid" {
  cat > "${TMP}/bad-config.sh" <<'CFG'
MPM_INTERVAL_SECONDS=not-a-number
CFG
  export MPM_CONFIG_PATH="${TMP}/bad-config.sh"

  run "${REPO_ROOT}/scripts/install.sh" --help
  [ "$status" -eq 0 ]
  [[ "$output" == *"Usage:"* ]]
}

@test "uninstall --help works when user config is invalid" {
  cat > "${TMP}/bad-config.sh" <<'CFG'
MPM_INTERVAL_SECONDS=not-a-number
CFG
  export MPM_CONFIG_PATH="${TMP}/bad-config.sh"

  run "${REPO_ROOT}/scripts/uninstall.sh" --help
  [ "$status" -eq 0 ]
  [[ "$output" == *"Usage:"* ]]
}
