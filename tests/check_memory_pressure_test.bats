#!/usr/bin/env bats
# Integration tests for scripts/check_memory_pressure.sh.

setup() {
  REPO_ROOT="$(cd "${BATS_TEST_DIRNAME}/.." && pwd)"
  TMP="$(mktemp -d)"
  STUB="${TMP}/bin"
  mkdir -p "${STUB}"

  export MPM_LOG_PATH="${TMP}/log.jsonl"
  export MPM_STATE_PATH="${TMP}/state.json"
  export MPM_NOTIFICATION_BACKEND=stderr
  export MPM_RED_COOLDOWN_SECONDS=600
  export MPM_SWAP_COOLDOWN_SECONDS=900
  export MPM_SWAP_THRESHOLD_MIB=64
}

teardown() {
  rm -rf "${TMP}"
}

# stub_path <pressure-fixture> <swap-fixture>
# writes stub binaries on PATH that emit fixture content for the keys
# the entrypoint reads.
stub_path() {
  local pressure_fix="$1" swap_fix="$2"
  cat > "${STUB}/sysctl" <<STUB
#!/bin/bash
case "\$1" in
  kern.memorystatus_vm_pressure_level) cat "${REPO_ROOT}/tests/fixtures/${pressure_fix}" ;;
  kern.memorystatus_level) cat "${REPO_ROOT}/tests/fixtures/sysctl_memorystatus_level.txt" ;;
  vm.swapusage) cat "${REPO_ROOT}/tests/fixtures/${swap_fix}" ;;
esac
STUB
  cat > "${STUB}/vm_stat" <<STUB
#!/bin/bash
cat "${REPO_ROOT}/tests/fixtures/vm_stat_macos26.txt"
STUB
  chmod +x "${STUB}/sysctl" "${STUB}/vm_stat"
  export PATH="${STUB}:${PATH}"
}

@test "normal load: no notification, one sample_taken log" {
  stub_path sysctl_pressure_level_normal.txt sysctl_swapusage_inactive.txt
  run "${REPO_ROOT}/scripts/check_memory_pressure.sh"
  [ "$status" -eq 0 ]
  run cat "${MPM_LOG_PATH}"
  [[ "$output" == *'"event":"sample_taken"'* ]]
  [[ "$output" != *'"event":"alert_fired"'* ]]
}

@test "red pressure with no prior alert: notification fires once" {
  stub_path sysctl_pressure_level_critical.txt sysctl_swapusage_inactive.txt
  run "${REPO_ROOT}/scripts/check_memory_pressure.sh"
  [ "$status" -eq 0 ]
  [[ "$output" == *"notify: title=Memory pressure: red"* ]]
  run cat "${MPM_LOG_PATH}"
  [[ "$output" == *'"event":"alert_fired"'* ]]
  [[ "$output" == *'"kind":"red_pressure"'* ]]
}

@test "red pressure within cooldown: alert suppressed" {
  stub_path sysctl_pressure_level_critical.txt sysctl_swapusage_inactive.txt
  # First run — fires.
  "${REPO_ROOT}/scripts/check_memory_pressure.sh" 2> /dev/null
  # Second run — suppressed.
  run "${REPO_ROOT}/scripts/check_memory_pressure.sh"
  [ "$status" -eq 0 ]
  [[ "$output" != *"notify: title=Memory pressure"* ]]
  run cat "${MPM_LOG_PATH}"
  [[ "$output" == *'"event":"alert_suppressed"'* ]]
}

@test "swap in use independently triggers alert" {
  stub_path sysctl_pressure_level_normal.txt sysctl_swapusage_active.txt
  run "${REPO_ROOT}/scripts/check_memory_pressure.sh"
  [ "$status" -eq 0 ]
  [[ "$output" == *"notify: title=Swap in use"* ]]
  run cat "${MPM_LOG_PATH}"
  [[ "$output" == *'"kind":"swap_in_use"'* ]]
}

@test "red and swap simultaneously: two alerts in one tick" {
  stub_path sysctl_pressure_level_critical.txt sysctl_swapusage_active.txt
  run "${REPO_ROOT}/scripts/check_memory_pressure.sh"
  [ "$status" -eq 0 ]
  [[ "$output" == *"notify: title=Memory pressure: red"* ]]
  [[ "$output" == *"notify: title=Swap in use"* ]]
}
