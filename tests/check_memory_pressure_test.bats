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
  export MPM_CONFIG_PATH="${TMP}/missing-config.sh"
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
  [[ "$output" == *"notify: title=Memory pressure critical"* ]]
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
  [[ "$output" != *"notify: title=Memory pressure critical"* ]]
  run cat "${MPM_LOG_PATH}"
  [[ "$output" == *'"event":"alert_suppressed"'* ]]
}

@test "swap in use independently triggers alert" {
  stub_path sysctl_pressure_level_normal.txt sysctl_swapusage_active.txt
  run "${REPO_ROOT}/scripts/check_memory_pressure.sh"
  [ "$status" -eq 0 ]
  [[ "$output" == *"notify: title=Swap started"* ]]
  run cat "${MPM_LOG_PATH}"
  [[ "$output" == *'"kind":"swap_in_use"'* ]]
}

@test "persistent swap does not re-alert after cooldown until swap clears" {
  stub_path sysctl_pressure_level_normal.txt sysctl_swapusage_active.txt
  TEST_NOW=1000000000 TEST_NOW_ISO="2001-09-09T01:46:40+00:00" \
    "${REPO_ROOT}/scripts/check_memory_pressure.sh" 2> /dev/null

  run env TEST_NOW=1000001000 TEST_NOW_ISO="2001-09-09T02:03:20+00:00" \
    "${REPO_ROOT}/scripts/check_memory_pressure.sh"
  [ "$status" -eq 0 ]
  [[ "$output" != *"notify: title=Swap started"* ]]
  run cat "${MPM_LOG_PATH}"
  [[ "$output" == *'"reason":"still_active"'* ]]
}

@test "swap clears then returns: alert fires again after cooldown" {
  stub_path sysctl_pressure_level_normal.txt sysctl_swapusage_active.txt
  TEST_NOW=1000000000 TEST_NOW_ISO="2001-09-09T01:46:40+00:00" \
    "${REPO_ROOT}/scripts/check_memory_pressure.sh" 2> /dev/null

  stub_path sysctl_pressure_level_normal.txt sysctl_swapusage_inactive.txt
  TEST_NOW=1000000100 TEST_NOW_ISO="2001-09-09T01:48:20+00:00" \
    "${REPO_ROOT}/scripts/check_memory_pressure.sh" 2> /dev/null

  stub_path sysctl_pressure_level_normal.txt sysctl_swapusage_active.txt
  run env TEST_NOW=1000001000 TEST_NOW_ISO="2001-09-09T02:03:20+00:00" \
    "${REPO_ROOT}/scripts/check_memory_pressure.sh"
  [ "$status" -eq 0 ]
  [[ "$output" == *"notify: title=Swap started"* ]]
}

@test "red and swap simultaneously: one red notification covers both" {
  stub_path sysctl_pressure_level_critical.txt sysctl_swapusage_active.txt
  run "${REPO_ROOT}/scripts/check_memory_pressure.sh"
  [ "$status" -eq 0 ]
  [[ "$output" == *"notify: title=Memory pressure critical"* ]]
  [[ "$output" != *"notify: title=Swap started"* ]]
  run cat "${MPM_LOG_PATH}"
  [[ "$output" == *'"event":"alert_coalesced"'* ]]
}

@test "failing notification backend records cooldown and exits cleanly" {
  stub_path sysctl_pressure_level_critical.txt sysctl_swapusage_inactive.txt
  cat > "${STUB}/osascript" <<'STUB'
#!/bin/bash
exit 7
STUB
  chmod +x "${STUB}/osascript"

  run env MPM_NOTIFICATION_BACKEND=osascript "${REPO_ROOT}/scripts/check_memory_pressure.sh"
  [ "$status" -eq 0 ]
  [ -f "${MPM_STATE_PATH}" ]
  run cat "${MPM_LOG_PATH}"
  [[ "$output" == *'"event":"notify_failed"'* ]]
  [[ "$output" == *'"event":"alert_failed"'* ]]
}

@test "malformed primary pressure level fails the tick" {
  stub_path sysctl_pressure_level_normal.txt sysctl_swapusage_inactive.txt
  printf 'kern.memorystatus_vm_pressure_level: nope\n' > "${STUB}/bad_pressure"
  cat > "${STUB}/sysctl" <<STUB
#!/bin/bash
case "\$1" in
  kern.memorystatus_vm_pressure_level) cat "${STUB}/bad_pressure" ;;
  kern.memorystatus_level) cat "${REPO_ROOT}/tests/fixtures/sysctl_memorystatus_level.txt" ;;
  vm.swapusage) cat "${REPO_ROOT}/tests/fixtures/sysctl_swapusage_inactive.txt" ;;
esac
STUB
  chmod +x "${STUB}/sysctl"

  run "${REPO_ROOT}/scripts/check_memory_pressure.sh"
  [ "$status" -ne 0 ]
  run cat "${MPM_LOG_PATH}"
  [[ "$output" == *'"event":"sample_failed"'* ]]
  [[ "$output" != *'"event":"sample_taken"'* ]]
}
