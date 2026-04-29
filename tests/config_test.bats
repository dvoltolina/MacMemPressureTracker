#!/usr/bin/env bats
# Tests for lib/config.sh — strict config parser and validation.

setup() {
  REPO_ROOT="$(cd "${BATS_TEST_DIRNAME}/.." && pwd)"
  TMP="$(mktemp -d)"
  export HOME="${TMP}/home"
  mkdir -p "${HOME}/.config/memory-pressure-monitor"
}

teardown() {
  rm -rf "${TMP}"
}

@test "config::load accepts whitelisted KEY=value overrides" {
  cat > "${HOME}/.config/memory-pressure-monitor/config.sh" << 'CFG'
# comment
MPM_INTERVAL_SECONDS=45
MPM_SWAP_THRESHOLD_MIB=128 # inline comment
MPM_NOTIFICATION_BACKEND="stderr"
CFG
  printf 'MPM_LOG_PATH="%s/memory pressure test.log"\n' "${TMP}" >> "${HOME}/.config/memory-pressure-monitor/config.sh"

  run bash -c "source '${REPO_ROOT}/lib/config.sh'; config::load; printf '%s %s %s %s' \"\${MPM_INTERVAL_SECONDS}\" \"\${MPM_SWAP_THRESHOLD_MIB}\" \"\${MPM_NOTIFICATION_BACKEND}\" \"\${MPM_LOG_PATH}\""
  [ "$status" -eq 0 ]
  [ "$output" = "45 128 stderr ${TMP}/memory pressure test.log" ]
}

@test "config::load rejects unsupported keys instead of executing shell" {
  cat > "${HOME}/.config/memory-pressure-monitor/config.sh" << 'CFG'
MPM_INTERVAL_SECONDS=45
BAD_KEY=touch /tmp/should-not-run
CFG

  run bash -c "source '${REPO_ROOT}/lib/config.sh'; config::load"
  [ "$status" -ne 0 ]
  [[ "$output" == *"unsupported key"* ]]
}

@test "config::load rejects invalid numeric values" {
  cat > "${HOME}/.config/memory-pressure-monitor/config.sh" << 'CFG'
MPM_SWAP_THRESHOLD_MIB=abc
CFG

  run bash -c "source '${REPO_ROOT}/lib/config.sh'; config::load"
  [ "$status" -ne 0 ]
  [[ "$output" == *"MPM_SWAP_THRESHOLD_MIB"* ]]
}

@test "config::load rejects relative log paths" {
  cat > "${HOME}/.config/memory-pressure-monitor/config.sh" << 'CFG'
MPM_LOG_PATH=relative.log
CFG

  run bash -c "source '${REPO_ROOT}/lib/config.sh'; config::load"
  [ "$status" -ne 0 ]
  [[ "$output" == *"MPM_LOG_PATH"* ]]
}

@test "config::load rejects directory log paths" {
  mkdir -p "${TMP}/logs-as-dir"
  cat > "${HOME}/.config/memory-pressure-monitor/config.sh" << CFG
MPM_LOG_PATH=${TMP}/logs-as-dir
CFG

  run bash -c "source '${REPO_ROOT}/lib/config.sh'; config::load"
  [ "$status" -ne 0 ]
  [[ "$output" == *"regular file"* ]]
}

@test "config::load rejects symlink state paths" {
  touch "${TMP}/real-state.json"
  ln -s "${TMP}/real-state.json" "${TMP}/linked-state.json"
  cat > "${HOME}/.config/memory-pressure-monitor/config.sh" << CFG
MPM_STATE_PATH=${TMP}/linked-state.json
CFG

  run bash -c "source '${REPO_ROOT}/lib/config.sh'; config::load"
  [ "$status" -ne 0 ]
  [[ "$output" == *"symlink"* ]]
}
