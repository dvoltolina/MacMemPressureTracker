#!/usr/bin/env bats
# Tests for lib/state.sh — debounce state file manager.

setup() {
  REPO_ROOT="$(cd "${BATS_TEST_DIRNAME}/.." && pwd)"
  TMP="$(mktemp -d)"
  export MPM_STATE_PATH="${TMP}/state.json"
  export MPM_LOG_PATH="${TMP}/log.jsonl"
  export MPM_RED_COOLDOWN_SECONDS=600
  export MPM_SWAP_COOLDOWN_SECONDS=900
  # shellcheck source=/dev/null
  source "${REPO_ROOT}/lib/log.sh"
  # shellcheck source=/dev/null
  source "${REPO_ROOT}/lib/state.sh"
}

teardown() {
  rm -rf "${TMP}"
}

@test "should_alert: missing state file returns 0 (allow)" {
  run state::should_alert red_pressure
  [ "$status" -eq 0 ]
}

@test "record_alert: writes valid JSON containing kind timestamp" {
  TEST_NOW_ISO="2026-04-27T08:45:00-07:00" state::record_alert red_pressure
  [ -f "${MPM_STATE_PATH}" ]
  run cat "${MPM_STATE_PATH}"
  [[ "$output" == *'"red_pressure":"2026-04-27T08:45:00-07:00"'* ]]
  [[ "$output" == *'"swap_in_use":null'* ]]
  [[ "$output" == *'"swap_active":false'* ]]
}

@test "should_alert: just-recorded alert is suppressed within cooldown" {
  TEST_NOW_ISO="2026-04-27T08:45:00-07:00" \
    TEST_NOW=$(date -j -f "%Y-%m-%dT%H:%M:%S%z" "2026-04-27T08:45:00-0700" +%s) \
    state::record_alert red_pressure

  # 5 minutes later — still inside the 10-minute cooldown.
  later=$(($(date -j -f "%Y-%m-%dT%H:%M:%S%z" "2026-04-27T08:45:00-0700" +%s) + 300))
  run env TEST_NOW="${later}" bash -c "source '${REPO_ROOT}/lib/log.sh'; source '${REPO_ROOT}/lib/state.sh'; state::should_alert red_pressure"
  [ "$status" -eq 1 ]
}

@test "should_alert: cooldown elapsed returns 0" {
  TEST_NOW_ISO="2026-04-27T08:45:00-07:00" \
    TEST_NOW=$(date -j -f "%Y-%m-%dT%H:%M:%S%z" "2026-04-27T08:45:00-0700" +%s) \
    state::record_alert red_pressure

  # 11 minutes later — past the 10-minute red cooldown.
  later=$(($(date -j -f "%Y-%m-%dT%H:%M:%S%z" "2026-04-27T08:45:00-0700" +%s) + 660))
  run env TEST_NOW="${later}" bash -c "source '${REPO_ROOT}/lib/log.sh'; source '${REPO_ROOT}/lib/state.sh'; state::should_alert red_pressure"
  [ "$status" -eq 0 ]
}

@test "record_alert preserves the other kind's timestamp" {
  TEST_NOW_ISO="2026-04-27T08:00:00-07:00" state::record_alert red_pressure
  TEST_NOW_ISO="2026-04-27T09:00:00-07:00" state::record_alert swap_in_use
  run cat "${MPM_STATE_PATH}"
  [[ "$output" == *'"red_pressure":"2026-04-27T08:00:00-07:00"'* ]]
  [[ "$output" == *'"swap_in_use":"2026-04-27T09:00:00-07:00"'* ]]
}

@test "corrupt state file: should_alert returns 0 and logs warn" {
  printf 'this is not json at all' > "${MPM_STATE_PATH}"
  run state::should_alert red_pressure
  [ "$status" -eq 0 ]
}

@test "atomic write: no .tmp file left behind on success" {
  TEST_NOW_ISO="2026-04-27T08:45:00-07:00" state::record_alert red_pressure
  run bash -c "ls '${MPM_STATE_PATH}'.tmp.* 2>/dev/null | wc -l"
  [ "$(echo "$output" | tr -d ' ')" = "0" ]
}

@test "state::path returns the override" {
  run state::path
  [ "$output" = "${MPM_STATE_PATH}" ]
}

@test "state::reset removes the state file" {
  TEST_NOW_ISO="2026-04-27T08:45:00-07:00" state::record_alert red_pressure
  [ -f "${MPM_STATE_PATH}" ]
  state::reset
  [ ! -f "${MPM_STATE_PATH}" ]
}

@test "should_alert with unknown kind returns rc=2" {
  run state::should_alert garbage_kind
  [ "$status" -eq 2 ]
}

@test "swap_active toggles explicitly" {
  run state::swap_active
  [ "$status" -ne 0 ]

  state::set_swap_active true
  run state::swap_active
  [ "$status" -eq 0 ]

  state::set_swap_active false
  run state::swap_active
  [ "$status" -ne 0 ]
}

@test "record_alert swap_in_use marks swap active" {
  TEST_NOW_ISO="2026-04-27T08:45:00-07:00" state::record_alert swap_in_use
  run cat "${MPM_STATE_PATH}"
  [[ "$output" == *'"swap_in_use":"2026-04-27T08:45:00-07:00"'* ]]
  [[ "$output" == *'"swap_active":true'* ]]
}

@test "should_alert parses pretty JSON with whitespace" {
  cat > "${MPM_STATE_PATH}" <<'JSON'
{
  "schema": 1,
  "last_alert": {
    "red_pressure": "2026-04-27T08:45:00-07:00",
    "swap_in_use": null
  },
  "swap_active": false
}
JSON

  now=$(($(date -j -f "%Y-%m-%dT%H:%M:%S%z" "2026-04-27T08:45:00-0700" +%s) + 300))
  run env TEST_NOW="${now}" bash -c "source '${REPO_ROOT}/lib/log.sh'; source '${REPO_ROOT}/lib/state.sh'; state::should_alert red_pressure"
  [ "$status" -eq 1 ]
}

@test "set_swap_active preserves timestamps from pretty JSON" {
  cat > "${MPM_STATE_PATH}" <<'JSON'
{
  "schema": 1,
  "last_alert": {
    "red_pressure": "2026-04-27T08:00:00-07:00",
    "swap_in_use": "2026-04-27T09:00:00-07:00"
  },
  "swap_active": true
}
JSON

  state::set_swap_active false
  run cat "${MPM_STATE_PATH}"
  [[ "$output" == *'"red_pressure":"2026-04-27T08:00:00-07:00"'* ]]
  [[ "$output" == *'"swap_in_use":"2026-04-27T09:00:00-07:00"'* ]]
  [[ "$output" == *'"swap_active":false'* ]]
}

@test "state with schema but missing alert keys logs corruption warning" {
  printf '{"schema":1,' > "${MPM_STATE_PATH}"
  run state::should_alert red_pressure
  [ "$status" -eq 0 ]
  run cat "${MPM_LOG_PATH}"
  [[ "$output" == *'"event":"state_corrupted"'* ]]
}
