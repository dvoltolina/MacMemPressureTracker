#!/usr/bin/env bats
# Tests for scripts/status.sh.

setup() {
  REPO_ROOT="$(cd "${BATS_TEST_DIRNAME}/.." && pwd)"
  TMP="$(mktemp -d)"
  STUB="${TMP}/bin"
  mkdir -p "${STUB}" "${TMP}/home"
  export HOME="${TMP}/home"
  export MPM_CONFIG_PATH="${TMP}/missing-config.sh"
  export MPM_TEST_ALLOW_PATH=1
  export PATH="${STUB}:${PATH}"
}

teardown() {
  rm -rf "${TMP}"
}

stub_launchctl() {
  local status="$1"
  cat > "${STUB}/launchctl" <<STUB
#!/bin/bash
case "\$1" in
  print) exit ${status} ;;
  *) exit 0 ;;
esac
STUB
  chmod +x "${STUB}/launchctl"
}

@test "status reports loaded launchd agent in human output" {
  stub_launchctl 0
  run "${REPO_ROOT}/scripts/status.sh"
  [ "$status" -eq 0 ]
  [[ "$output" == *"Launchd loaded:  yes"* ]]
  [[ "$output" == *"Status:"* ]]
  [[ "$output" == *"Plist installed:"* ]]
}

@test "status --json reports loaded false when launchctl print fails" {
  stub_launchctl 1
  run "${REPO_ROOT}/scripts/status.sh" --json
  [ "$status" -eq 0 ]
  [[ "$output" == *'"loaded":false'* ]]
  [[ "$output" == *'"health":"not_installed"'* ]]
  [[ "$output" == *'"installed":false'* ]]
}

@test "status survives invalid config and reports the error" {
  stub_launchctl 1
  cat > "${TMP}/bad-config.sh" <<'CFG'
MPM_INTERVAL_SECONDS=nope
CFG
  export MPM_CONFIG_PATH="${TMP}/bad-config.sh"

  run "${REPO_ROOT}/scripts/status.sh" --json
  [ "$status" -eq 0 ]
  [[ "$output" == *'"config_status":"invalid"'* ]]
  [[ "$output" == *'"health":"config_invalid"'* ]]
  [[ "$output" == *"MPM_INTERVAL_SECONDS"* ]]
}

@test "status honors valid custom log and state config paths" {
  stub_launchctl 1
  cat > "${TMP}/config.sh" <<CFG
MPM_LOG_PATH=${TMP}/custom.log
MPM_STATE_PATH=${TMP}/custom-state.json
CFG
  export MPM_CONFIG_PATH="${TMP}/config.sh"
  touch "${TMP}/custom.log" "${TMP}/custom-state.json"

  run "${REPO_ROOT}/scripts/status.sh" --json
  [ "$status" -eq 0 ]
  [[ "$output" == *"\"log_path\":\"${TMP}/custom.log\""* ]]
  [[ "$output" == *"\"state_path\":\"${TMP}/custom-state.json\""* ]]
}

@test "loaded agent with stale sample is not reported as running" {
  stub_launchctl 0
  cat > "${TMP}/config.sh" <<CFG
MPM_LOG_PATH=${TMP}/monitor.log
CFG
  export MPM_CONFIG_PATH="${TMP}/config.sh"
  printf '{"ts":"2001-09-09T01:46:40+00:00","level":"info","event":"sample_taken","zone":"normal"}\n' > "${TMP}/monitor.log"

  run env TEST_NOW=1000001000 "${REPO_ROOT}/scripts/status.sh" --json
  [ "$status" -eq 0 ]
  [[ "$output" == *'"health":"loaded_stale_sample"'* ]]
  [[ "$output" == *'"sample_fresh":false'* ]]
}

@test "status does not tail symlinked default log path" {
  stub_launchctl 1
  mkdir -p "${HOME}/Library/Logs"
  printf 'secret target content\n' > "${TMP}/target-log"
  ln -s "${TMP}/target-log" "${HOME}/Library/Logs/memory-pressure-monitor.log"

  run "${REPO_ROOT}/scripts/status.sh" --json
  [ "$status" -eq 0 ]
  [[ "$output" == *'"log_access":"unsafe"'* ]]
  [[ "$output" != *"secret target content"* ]]
}
